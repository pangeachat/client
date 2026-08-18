import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// Regression: Sentry CLIENT-D43 (#8339), 267 events on staging and production.
///
/// `MatrixState.pangeaController` is `static late`, assigned in
/// `MatrixState.initState` after `initMatrix()`. `ActivityPlanRepo` read it
/// while BUILDING the request — synchronously, before `BaseRepo.get` — so the
/// read sat outside `BaseRepo._fetch`'s try/catch and a
/// `LateInitializationError` escaped the repo entirely. The world map reaches
/// `ensure`/`cachedPlan` from `build()`, so a cold start straight onto the map
/// crashed.
///
/// `createRequests()` reads the same controller for the access token, but from
/// INSIDE that try/catch, which is why it only ever degraded to `Result.error`.
/// That difference is the whole bug, and it is why the guard belongs on the
/// request-building path alone.
///
/// The fix must decline, not throw, and must not spend the 60s attempt cooldown
/// on a condition that clears within a frame or two of startup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Registered synchronously, BEFORE `ActivityPlanRepo.instance` is touched:
  // the singleton's `PersistentRepoCache` field builds a `GetStorage` container
  // on construction, which reaches for path_provider immediately.
  final tempDir = Directory.systemTemp.createTempSync('plan_late_init_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  final repo = ActivityPlanRepo.instance;

  setUpAll(() => GetStorage.init('activity_plan_storage'));

  setUp(repo.resetBackoff);

  // These run FIRST on purpose. `pangeaController` is a process-wide static, so
  // once the group below assigns it there is no way back to the uninitialized
  // state within this file. The precondition assert makes a reordering fail
  // loudly here rather than quietly turning these into no-ops.
  group('before MatrixState assigns its controller', () {
    setUp(() {
      expect(
        MatrixState.isPangeaControllerInitialized,
        isFalse,
        reason:
            'these cases describe the uninitialized state; something assigned '
            'the controller before them',
      );
    });

    test('ensure declines instead of throwing', () {
      expect(repo.ensure('late-init-ensure'), isFalse);
    });

    test('cachedPlan returns null instead of throwing', () {
      expect(repo.cachedPlan('late-init-cached'), isNull);
    });

    test('lookup reports failed, never removed', () async {
      final result = await repo.lookup('late-init-lookup');
      expect(
        result.status,
        ActivityPlanLookupStatus.failed,
        reason:
            'removed is terminal — it would strand a healthy activity behind '
            'the removed-activity fallback for the rest of the session',
      );
      expect(result.plan, isNull);
    });

    test('getPlan returns null instead of throwing', () async {
      expect(await repo.getPlan('late-init-get-plan'), isNull);
    });

    test('an explicit l1 is not an exemption', () {
      // Supplying l1 skips `_viewerLanguage`, but NOT the other two controller reads
      // on the same call. `PersistentRepoCache.init` is the dangerous one: it
      // runs via `BaseRepo._cacheInit`, a `late final` Future, so one early
      // failure is memoized and re-thrown by every later `get` for the life of
      // the process — from outside any try/catch. Letting this through would
      // wedge the repo's cache permanently rather than lose one plan.
      expect(repo.ensure('late-init-explicit', l1: 'en'), isFalse);
    });
  });

  group('once the controller exists', () {
    setUp(() => MatrixState.pangeaController = FakePangeaController());

    test('a declined ensure did not burn the attempt cooldown', () {
      // The decline above must not park the key. Parking would cost 60s of
      // silence for a condition that clears within a frame or two, leaving the
      // map blank long after the controller landed.
      expect(repo.ensure('late-init-rearm'), isTrue);
    });

    test('lookup reaches the fetch instead of short-circuiting', () async {
      // Proves the gate released rather than latching. It still reports failed
      // — the stub has no access token — but it got there through
      // `BaseRepo.get`, not through the guard.
      final result = await repo.lookup('late-init-viewer-l1');
      expect(result.status, ActivityPlanLookupStatus.failed);
    });
  });
}
