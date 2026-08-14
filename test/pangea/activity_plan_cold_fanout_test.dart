import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// Regression: staging 2026-08-14, `@ggurdin` 17:58:08 UTC.
///
/// 18 distinct `/choreo/v2/activity/{id}` reads left the client in 30ms, then
/// 11 more in 4ms. The choreographer budgets every `/choreo/*` path together
/// (60 per 60s per user), so the burst spent the whole minute's budget and the
/// next unrelated call — `/choreo/tokenize`, which backs free message
/// rendering — was refused for the rest of the window.
///
/// The backoff added for the 2026-08-04 incident could not prevent this. Every
/// guard in `ensure()` is temporal (`_nextAttempt`, `_rateLimitedUntil`) or
/// outcome-keyed (`_resolved`, `_confirmedRemoved`, `_hydrating`), and on a
/// COLD view all of them are empty by definition: nothing has resolved, nothing
/// has been attempted, and no pause can be armed because no response has come
/// back yet. `ensure()` is reached from `build()`, so K cards in one frame is K
/// synchronous passes that each clear every guard. Backoff reacts to a
/// response; the first wave happens before any response exists.
///
/// Real callers that fan out one `ensure()` per rendered item:
///  - `world_map_view.dart` (per featured pin)
///  - `activity_room_extension.dart` (per room, via the sync `activityPlan`
///    getter reached in `build()`)
///  - `room_summary_extension.dart` (per room summary)
///
/// Harness note: copied from `activity_plan_fetch_backoff_test.dart`. The stub
/// controller gets the repo past its "is `pangeaController` assigned" gate but
/// carries no access token, so every fetch fails inside `BaseRepo._fetch` and
/// surfaces as `Result.error`. That does not affect what is under test: the
/// dispatch decision, and the parking that follows it, are synchronous.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Registered before `ActivityPlanRepo.instance` is touched — the singleton
  // builds a GetStorage container on construction, which reaches for
  // path_provider immediately.
  final tempDir = Directory.systemTemp.createTempSync('plan_fanout_repro');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  final repo = ActivityPlanRepo.instance;
  var clock = DateTime(2026, 8, 14, 17, 58);

  setUpAll(() {
    MatrixState.pangeaController = FakePangeaController();
    return GetStorage.init('activity_plan_storage');
  });

  setUp(() {
    clock = DateTime(2026, 8, 14, 17, 58);
    ActivityPlanRepo.now = () => clock;
    repo.resetBackoff();
  });

  tearDownAll(() => ActivityPlanRepo.now = DateTime.now);

  /// Lets in-flight fetches settle so the queue drains and `_inFlight` returns
  /// to zero before the next test asserts on it.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  group('cold-frame fan-out', () {
    test('one frame over K cold keys dispatches at most the in-flight cap', () async {
      // One frame, no awaits: exactly what `build()` does when a list view
      // renders K activity cards, and why no reactive backoff can help — every
      // one of these runs before the first response exists.
      const k = 60;
      var accepted = 0;
      for (var i = 0; i < k; i++) {
        if (repo.ensure('cold-$i', l1: 'en')) accepted++;
      }

      expect(
        accepted,
        k,
        reason: 'every cold key is legitimate work and must be accepted',
      );
      expect(
        repo.inFlightCount,
        lessThanOrEqualTo(6),
        reason:
            'the frame put ${repo.inFlightCount} requests on the wire at once. '
            'The per-user /choreo/* budget is 60/min shared with tokenize, TTS, '
            'STT and translate, so one cold frame must not be able to spend it',
      );
      expect(
        repo.queuedCount,
        k - repo.inFlightCount,
        reason: 'the remainder is deferred, not dropped',
      );

      await settle();
    });

    test('a queued backlog is dropped when the backend rate-limits us', () async {
      for (var i = 0; i < 30; i++) {
        repo.ensure('burst-$i', l1: 'en');
      }
      expect(repo.queuedCount, greaterThan(0));

      // A 429 lands while the backlog waits. Draining it anyway would spend the
      // next window the moment the pause lifts: the same burst, spread thin.
      repo.rateLimitedForTesting(const Duration(seconds: 60));
      await settle();

      expect(
        repo.queuedCount,
        0,
        reason: 'a paused repo must not keep feeding the wire from its backlog',
      );
    });

    test('the same activity under two version pins is two keys', () {
      // Why the 17:58:08 and 17:58:20 waves shared ids (0fe94762, 60538810)
      // despite a 60s per-key cooldown set by the first wave: storageKey is
      // `activityId_l1_version`, world_map_view calls ensure(id) unpinned and
      // activity_room_extension calls ensure(id, version: ...). Same activity,
      // different key, so the cooldown never applied. Left as-is — collapsing
      // them is a caching decision, not a rate one — but both now share the
      // in-flight cap, so the pair can no longer burst.
      expect(repo.ensure('shared-id', l1: 'en'), isTrue);
      expect(repo.ensure('shared-id', l1: 'en', version: 'v7'), isTrue);
      expect(repo.inFlightCount, lessThanOrEqualTo(6));
    });
  });

  group('revalidate honors the repo-wide pause', () {
    test('a revalidating call is suppressed while paused', () {
      // The pause check used to live inside `if (!doRevalidate)`, which a
      // revalidating call skips wholesale, so it walked straight through an
      // armed pause. A 429 is a statement about RATE, not about a key.
      repo.rateLimitedForTesting(const Duration(seconds: 60));

      expect(repo.ensure('reval-1', l1: 'en', revalidate: true), isFalse);
      expect(repo.inFlightCount, 0);
    });

    test('a suppressed revalidate does not spend its once-per-session token', () {
      repo.rateLimitedForTesting(const Duration(seconds: 60));
      expect(repo.ensure('reval-2', l1: 'en', revalidate: true), isFalse);

      clock = clock.add(const Duration(seconds: 61));
      expect(
        repo.ensure('reval-2', l1: 'en', revalidate: true),
        isTrue,
        reason:
            'the revalidate token is once per (activity, l1) per app session; '
            'a call that never fetched must not consume it, or a re-translation '
            'would never reach this client',
      );
    });
  });
}
