import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_fetch_response.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

/// Regression: staging 2026-08-04.
///
/// `ensure()` is reached from `build()`, which runs per frame. Its guards used
/// to be a whitelist of reasons NOT to fetch — 404 (`_confirmedRemoved`), in
/// flight (`_hydrating`), success (`_resolved`). A 429, a 5xx, or a mapping
/// throw matched none of them, so "no guard matched" meant "re-fetch at frame
/// rate". A 429 returns in ~47ms against ~5s for a success, so the throttle
/// engaging *increased* load ~100x and kept the per-user budget exhausted.
/// 52,475 requests/day, 190 per activity, ending in 451 user-facing 503s.
///
/// The fix parks a key on the ATTEMPT, before the I/O, so it is total over
/// outcomes nobody enumerated — including ones added later.
///
/// These tests drive the real singleton. `createRequests()` reaches into
/// `MatrixState`, which does not exist under test, so every fetch fails inside
/// `BaseRepo._fetch`'s try/catch and surfaces as `Result.error`. That is
/// exactly the shape under test: a failing fetch must not re-arm.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Registered synchronously, BEFORE `ActivityPlanRepo.instance` is touched:
  // the singleton's `PersistentRepoCache` field builds a `GetStorage`
  // container on construction, which reaches for path_provider immediately.
  // Doing this in `setUpAll` is too late — the singleton is already built.
  final tempDir = Directory.systemTemp.createTempSync('plan_backoff_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  final repo = ActivityPlanRepo.instance;
  var clock = DateTime(2026, 8, 4, 12);

  setUpAll(() => GetStorage.init('activity_plan_storage'));

  setUp(() {
    clock = DateTime(2026, 8, 4, 12);
    ActivityPlanRepo.now = () => clock;
    repo.resetBackoff();
  });

  tearDownAll(() => ActivityPlanRepo.now = DateTime.now);

  /// Lets the in-flight fetch settle so `_hydrating` clears.
  ///
  /// This matters: while a fetch is in flight the PRE-EXISTING in-flight guard
  /// suppresses re-entry all by itself. A test that never settles would pass
  /// against the old code too, and prove nothing. Every assertion below that
  /// targets the new backoff runs only AFTER the failure has landed — which is
  /// precisely the frame on which the old code re-armed.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  group('attempt cooldown', () {
    test('a settled failure does not re-arm on later frames', () async {
      expect(repo.ensure('storm-1', l1: 'en'), isTrue);
      await settle();

      var issued = 0;
      for (var i = 0; i < 100; i++) {
        if (repo.ensure('storm-1', l1: 'en')) issued++;
      }

      expect(
        issued,
        0,
        reason: '100 post-failure frames issued $issued fetches; '
            'before the fix this was 100 — the incident itself',
      );
    });

    test('re-attempt is allowed once the cooldown lapses', () async {
      expect(repo.ensure('lapse-1', l1: 'en'), isTrue);
      await settle();
      expect(repo.ensure('lapse-1', l1: 'en'), isFalse);

      clock = clock.add(const Duration(seconds: 61));
      expect(
        repo.ensure('lapse-1', l1: 'en'),
        isTrue,
        reason: 'backoff must expire — a transient failure is not terminal',
      );
    });

    test('the cooldown is per key, not global', () {
      expect(repo.ensure('key-a', l1: 'en'), isTrue);
      expect(
        repo.ensure('key-b', l1: 'en'),
        isTrue,
        reason: 'one parked key must not block an unrelated activity',
      );
    });

    test('distinct l1 variants are distinct keys', () {
      expect(repo.ensure('multi', l1: 'en'), isTrue);
      expect(repo.ensure('multi', l1: 'es'), isTrue);
      expect(repo.ensure('multi', l1: 'en'), isFalse);
    });
  });

  group('rate-limit pause', () {
    test('a 429 pauses the whole repo, not just the key that saw it', () {
      // Per-key backoff alone cannot honour a 429: the map hydrates one key per
      // visible pin, so K keys each backing off independently still emit
      // K/cooldown requests. At the incident's K=104 that is 104/min against a
      // 60/min budget — still saturated.
      repo.rateLimitedForTesting(const Duration(seconds: 60));

      expect(repo.ensure('any-a', l1: 'en'), isFalse);
      expect(repo.ensure('any-b', l1: 'en'), isFalse);
      expect(repo.ensure('any-c', l1: 'en'), isFalse);
    });

    test('the pause lifts on its own', () {
      repo.rateLimitedForTesting(const Duration(seconds: 60));
      expect(repo.ensure('lift-1', l1: 'en'), isFalse);

      clock = clock.add(const Duration(seconds: 61));
      expect(repo.ensure('lift-1', l1: 'en'), isTrue);
    });
  });

  group('shouldCache refuses an unmappable body', () {
    ActivityPlanFetchResponse resp(Map<String, dynamic> plan) =>
        ActivityPlanFetchResponse(rawPlan: plan, l1: 'en', versionId: 'v1');

    test('a healthy plan is cached', () {
      expect(
        repo.shouldCache(
          resp({
            'activity_id': 'a1',
            'roles': [
              {'role_id': 'r1', 'name': 'Cliente'},
            ],
          }),
        ),
        isTrue,
      );
    });

    test('a body whose mapping throws is NOT written to disk', () {
      // `.plan` is a LAZY getter, so BaseRepo.get() persists before anything
      // maps it. Without this hook a poison body would sit in the cache for the
      // full TTL and be re-thrown by cachedPlan() from build(), every frame.
      expect(
        repo.shouldCache(resp({'roles': []})), // no activity_id -> throws
        isFalse,
      );
    });
  });

  group('classifyLookupError', () {
    test('404 is terminal, via the typed exception Requests actually throws', () {
      // Requests throws PangeaHttpException, never a raw http.Response, so a
      // check written against Response would silently never match and 404s
      // would loop like everything else.
      expect(
        ActivityPlanRepo.classifyLookupError(
          PangeaHttpException(statusCode: 404, method: 'GET', path: '/a/{id}'),
        ),
        ActivityPlanLookupStatus.removed,
      );
    });

    test('429 is retryable, not terminal', () {
      expect(
        ActivityPlanRepo.classifyLookupError(
          PangeaHttpException(statusCode: 429, method: 'GET', path: '/a/{id}'),
        ),
        ActivityPlanLookupStatus.failed,
      );
    });
  });
}
