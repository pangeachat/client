import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// Regression: Sentry CLIENT-EB0 — 2,766 events / 29 users since 2026-08-19
/// (#8691).
///
/// The in-session gate from #8359 caps a confirmed 404 at one fetch + one
/// report per activity id per app session — but the set was in-memory, so
/// every NEW session re-fetched and re-reported every known-dead id: ~20
/// distinct ids each re-reported 17–36 times over 7 days, all from builds
/// that already carried the in-session gate.
///
/// What is pinned here: the confirmed-removed verdict is persisted, so the
/// next app session answers "removed" from disk without a request or a
/// report; the verdict lapses after the retention window so a repaired
/// activity comes back on its own; an explicit refresh still clears it; and
/// a 404 spends a once-per-id report key so within a session it cannot
/// report twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Registered synchronously, BEFORE `ActivityPlanRepo.instance` is touched:
  // the singleton's `PersistentRepoCache` field builds a `GetStorage`
  // container on construction, which reaches for path_provider immediately.
  final tempDir = Directory.systemTemp.createTempSync('plan_persist_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  var clock = DateTime(2026, 9, 1, 12);

  setUpAll(() async {
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('activity_plan_storage');
  });

  setUp(() {
    clock = DateTime(2026, 9, 1, 12);
    ActivityPlanRepo.now = () => clock;
    ErrorHandler.resetReportedOnceKeysForTest();
    // Clears both the in-memory and the persisted suppression state, so tests
    // cannot leak verdicts into each other through the shared box.
    ActivityPlanRepo.instance.resetBackoff();
  });

  tearDownAll(() => ActivityPlanRepo.now = DateTime.now);

  /// Lets fire-and-forget persistence writes land before the next step reads.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 10));

  /// Serves every top-level `http` call from [handler] while [body] runs, and
  /// reports how many requests actually left the client.
  Future<int> countingClient(
    Future<http.Response> Function(http.Request) handler,
    Future<void> Function() body,
  ) async {
    var requests = 0;
    await http.runWithClient(body, () {
      return MockClient((request) {
        requests++;
        return handler(request);
      });
    });
    return requests;
  }

  Future<http.Response> gone(http.Request _) async =>
      http.Response('{"detail":"No canonical activity found"}', 404);

  Future<http.Response> unavailable(http.Request _) async =>
      http.Response('{"detail":"upstream down"}', 503);

  group('the confirmed-404 verdict survives an app restart', () {
    test('a fresh instance answers removed from disk, no request', () async {
      const activityId = 'gone-across-sessions';

      final first = await countingClient(gone, () async {
        final result = await ActivityPlanRepo.instance.lookup(
          activityId,
          l1: 'en',
        );
        expect(result.status, ActivityPlanLookupStatus.removed);
      });
      expect(first, 1, reason: 'the first read must actually ask the backend');
      await settle();

      // A fresh instance over the same box IS the next app session: empty
      // in-memory state, persisted storage intact.
      final nextSession = ActivityPlanRepo.forTesting();
      final later = await countingClient(gone, () async {
        final result = await nextSession.lookup(activityId, l1: 'en');
        expect(result.status, ActivityPlanLookupStatus.removed);
      });
      expect(
        later,
        0,
        reason:
            'the next session re-asked the backend about a known-dead id — '
            'the CLIENT-EB0 loop itself',
      );
    });

    test('ensure on the next session never reaches the network', () async {
      const activityId = 'gone-ensure-next-session';

      await countingClient(
        gone,
        () => ActivityPlanRepo.instance.getPlan(activityId, l1: 'en'),
      );
      await settle();

      final nextSession = ActivityPlanRepo.forTesting();
      final later = await countingClient(gone, () async {
        // ensure()'s synchronous gate cannot know disk state on a cold start;
        // suppression is enforced on the shared read path it drains into.
        nextSession.ensure(activityId, l1: 'en');
        await settle();
      });
      expect(later, 0);
    });

    test('only the 404 verdict persists — a 5xx stays retryable', () async {
      const goneId = 'gone-selective';
      const flakyId = 'flaky-selective';

      await countingClient(
        gone,
        () => ActivityPlanRepo.instance.getPlan(goneId, l1: 'en'),
      );
      await countingClient(
        unavailable,
        () => ActivityPlanRepo.instance.getPlan(flakyId, l1: 'en'),
      );
      await settle();

      final nextSession = ActivityPlanRepo.forTesting();
      expect(
        await countingClient(unavailable, () async {
          final result = await nextSession.lookup(flakyId, l1: 'en');
          expect(result.status, ActivityPlanLookupStatus.failed);
        }),
        1,
        reason: 'a transient failure must never be remembered as removed',
      );
      expect(
        await countingClient(gone, () => nextSession.getPlan(goneId, l1: 'en')),
        0,
      );
    });
  });

  group('the persisted verdict is not forever', () {
    test('it lapses after the retention window and re-checks', () async {
      const activityId = 'gone-until-retention';

      await countingClient(
        gone,
        () => ActivityPlanRepo.instance.getPlan(activityId, l1: 'en'),
      );
      await settle();

      clock = clock.add(const Duration(hours: 25));
      final nextSession = ActivityPlanRepo.forTesting();
      final later = await countingClient(gone, () async {
        final result = await nextSession.lookup(activityId, l1: 'en');
        expect(result.status, ActivityPlanLookupStatus.removed);
      });
      expect(
        later,
        1,
        reason:
            'the verdict must expire — a repaired activity has to come back '
            'without every user hard-refreshing',
      );
    });

    test('an explicit refresh clears it for the next session too', () async {
      const activityId = 'gone-until-refresh';

      await countingClient(
        gone,
        () => ActivityPlanRepo.instance.getPlan(activityId, l1: 'en'),
      );
      await settle();

      ActivityPlanRepo.instance.resetBackoff();
      await settle();

      final nextSession = ActivityPlanRepo.forTesting();
      expect(
        await countingClient(
          gone,
          () => nextSession.getPlan(activityId, l1: 'en'),
        ),
        1,
        reason:
            'resetBackoff is the user-initiated-refresh seam; it must drop '
            'the persisted verdict, not just the in-memory one',
      );
    });
  });

  group('a 404 reports once per id per session', () {
    PangeaHttpException http404() => PangeaHttpException(
      statusCode: 404,
      method: 'GET',
      path: '/choreo/v2/activity/{id}',
    );

    test('the fetch spends the once-per-id key', () async {
      const activityId = 'gone-once-key';

      await countingClient(
        gone,
        () => ActivityPlanRepo.instance.getPlan(activityId, l1: 'en'),
      );

      expect(
        await ErrorHandler.logErrorOnce(
          key: 'activity-plan-404:$activityId',
          e: http404(),
          data: const {},
        ),
        isFalse,
        reason:
            'the 404 fetch must have reported through this key already — a '
            'second report on it within the session is pure event volume',
      );
    });

    test(
      'a 5xx does not spend a once key — every occurrence reports',
      () async {
        const activityId = 'flaky-no-once-key';

        await countingClient(
          unavailable,
          () => ActivityPlanRepo.instance.getPlan(activityId, l1: 'en'),
        );

        expect(
          await ErrorHandler.logErrorOnce(
            key: 'activity-plan-404:$activityId',
            e: http404(),
            data: const {},
          ),
          isTrue,
          reason: 'only the confirmed-404 path is capped to once per id',
        );
      },
    );

    test('reportOnceKey keys 404s by activity id, everything else null', () {
      final request = ActivityPlanFetchRequest(activityId: 'the-id', l1: 'en');
      expect(
        ActivityPlanRepo.instance.reportOnceKey(request, http404()),
        'activity-plan-404:the-id',
      );
      expect(
        ActivityPlanRepo.instance.reportOnceKey(
          request,
          PangeaHttpException(
            statusCode: 503,
            method: 'GET',
            path: '/choreo/v2/activity/{id}',
          ),
        ),
        isNull,
      );
    });
  });

  group('callers outside the repo consult the shared verdict', () {
    test('activityLearningObjectiveRefs skips a known-dead id', () async {
      const activityId = 'gone-lo-refs';

      await countingClient(
        gone,
        () => ActivityPlanRepo.instance.getPlan(activityId, l1: 'en'),
      );

      final later = await countingClient(gone, () async {
        final result = await QuestRepo.activityLearningObjectiveRefs(
          activityId,
        );
        // The same value its own 404 handling returns: removed reads as
        // "no refs".
        expect(result.asValue?.value, isEmpty);
      });
      expect(later, 0);
    });
  });
}
