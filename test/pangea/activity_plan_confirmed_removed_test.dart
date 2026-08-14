import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// Regression: Sentry CLIENT-DWH — 753 events / 9 users in 24h, all for ONE
/// activity id (#8359).
///
/// The repo has always remembered which ids the backend confirmed gone, but the
/// `_confirmedRemoved` gate sat inside [ActivityPlanRepo.ensure] alone. Callers
/// that reach [ActivityPlanRepo.lookup] / [ActivityPlanRepo.getPlan] directly —
/// the activity start page, the summary read — walked straight past it, so a
/// 404'd activity was re-requested for as long as the surface stayed open.
///
/// What is pinned here: the gate lives on the shared read path, so a confirmed
/// 404 costs exactly one request per activity id per app session, no matter
/// which entry point asks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Registered synchronously, BEFORE `ActivityPlanRepo.instance` is touched:
  // the singleton's `PersistentRepoCache` field builds a `GetStorage` container
  // on construction, which reaches for path_provider immediately. Doing this in
  // `setUpAll` is too late — the singleton is already built.
  final tempDir = Directory.systemTemp.createTempSync('plan_removed_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  final repo = ActivityPlanRepo.instance;

  setUpAll(() async {
    // Unlike the backoff suite, these tests must reach the network: the stub
    // controller therefore carries an access token so `createRequests()`
    // succeeds and the MockClient below is what answers.
    MatrixState.pangeaController = FakePangeaController(
      accessToken: 'test-token',
    );
    dotenv.testLoad(mergeWith: {'CHOREO_API': 'https://choreo.test'});
    await GetStorage.init('env_override');
    await GetStorage.init('activity_plan_storage');
  });

  setUp(repo.resetBackoff);

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
      http.Response('{"detail":"Activity not found"}', 404);

  Future<http.Response> unavailable(http.Request _) async =>
      http.Response('{"detail":"upstream down"}', 503);

  group('a confirmed 404 suppresses further reads', () {
    test('lookup answers removed from memory, with no second request', () async {
      const activityId = 'gone-lookup';

      final first = await countingClient(gone, () async {
        final result = await repo.lookup(activityId, l1: 'en');
        expect(result.status, ActivityPlanLookupStatus.removed);
      });
      expect(first, 1, reason: 'the first read must actually ask the backend');

      final later = await countingClient(gone, () async {
        for (var i = 0; i < 50; i++) {
          final result = await repo.lookup(activityId, l1: 'en');
          expect(result.status, ActivityPlanLookupStatus.removed);
        }
      });
      expect(
        later,
        0,
        reason:
            '50 further reads issued $later requests; before the fix this was '
            '50 — the CLIENT-DWH loop itself',
      );
    });

    test('getPlan is gated too — it delegates to lookup', () async {
      const activityId = 'gone-get-plan';

      await countingClient(gone, () => repo.getPlan(activityId, l1: 'en'));

      final later = await countingClient(gone, () async {
        expect(await repo.getPlan(activityId, l1: 'en'), isNull);
      });
      expect(later, 0);
    });

    test('a pinned-version read is gated by the same id', () async {
      // `_confirmedRemoved` keys on the activity id, not the storage key: the
      // activity is gone, so no version of it can resolve.
      const activityId = 'gone-versioned';

      await countingClient(gone, () => repo.getPlan(activityId, l1: 'en'));

      final later = await countingClient(gone, () async {
        final result = await repo.lookup(activityId, l1: 'en', version: 'v9');
        expect(result.status, ActivityPlanLookupStatus.removed);
      });
      expect(later, 0);
    });

    test('ensure still declines, and never reaches the network', () async {
      const activityId = 'gone-ensure';

      await countingClient(gone, () => repo.getPlan(activityId, l1: 'en'));

      final later = await countingClient(gone, () async {
        expect(repo.ensure(activityId, l1: 'en'), isFalse);
        expect(repo.ensure(activityId, l1: 'en', revalidate: true), isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(later, 0);
    });

    test('an unrelated activity is unaffected', () async {
      await countingClient(
        gone,
        () => repo.getPlan('gone-neighbour', l1: 'en'),
      );

      final later = await countingClient(gone, () async {
        final result = await repo.lookup('live-neighbour', l1: 'en');
        expect(result.status, ActivityPlanLookupStatus.removed);
      });
      expect(
        later,
        1,
        reason: 'one gone activity must not mute reads of every other id',
      );
    });
  });

  group('only a confirmed 404 suppresses', () {
    test('a 5xx stays retryable', () async {
      const activityId = 'flaky';

      final first = await countingClient(unavailable, () async {
        final result = await repo.lookup(activityId, l1: 'en');
        expect(result.status, ActivityPlanLookupStatus.failed);
      });
      expect(first, 1);

      final second = await countingClient(unavailable, () async {
        final result = await repo.lookup(activityId, l1: 'en');
        expect(result.status, ActivityPlanLookupStatus.failed);
      });
      expect(
        second,
        1,
        reason:
            'a transient failure is not terminal — the start page offers a '
            'retry, and it has to be able to reach the backend',
      );
    });
  });

  group('resetBackoff', () {
    test(
      'clears the removed gate so an explicit refresh can re-check',
      () async {
        const activityId = 'gone-then-refreshed';

        await countingClient(gone, () => repo.getPlan(activityId, l1: 'en'));
        expect(
          await countingClient(gone, () => repo.getPlan(activityId, l1: 'en')),
          0,
        );

        repo.resetBackoff();
        expect(
          await countingClient(gone, () => repo.getPlan(activityId, l1: 'en')),
          1,
          reason:
              'resetBackoff is the user-initiated-refresh seam; it must drop '
              'every suppression the repo holds, not just the cooldowns',
        );
      },
    );
  });
}
