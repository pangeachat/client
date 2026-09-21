import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/activity_sessions/activity_auto_save_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'get_test_client.dart';

/// Regression: Sentry CLIENT-EHY / EJ5 / EJD / EJ2 (#8712), 153 events in one
/// day on staging and present in production.
///
/// `MatrixState.initState` runs `initMatrix()` — which registers every restored
/// client and calls `ActivityAutoSaveService.start()` — BEFORE it assigns the
/// `static late` `MatrixState.pangeaController`. For a session that is already
/// logged in and already synced, `start()` passes both of its awaits without
/// suspending, so `_sweep()` reaches `_publishStarTotal()` synchronously inside
/// `initMatrix()`, and the unguarded controller read threw
/// `LateInitializationError` out of an unawaited future.
///
/// The service must decline the publish, not throw. It is not a loss: the total
/// only ever rises and the next sweep republishes.
class _FakeAnalyticsService implements AnalyticsDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  // start() touches ActivityPlanRepo.instance, whose PersistentRepoCache field
  // builds a GetStorage container on construction and reaches for
  // path_provider immediately — so this is registered before the singleton is
  // ever resolved.
  final tempDir = Directory.systemTemp.createTempSync('autosave_late_init');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  setUpAll(() => GetStorage.init('activity_plan_storage'));

  test(
    'start() completes instead of throwing when the controller is unset',
    () async {
      // Precondition, not decoration: `pangeaController` is a process-wide
      // static, so anything that assigned it would silently turn this into a
      // no-op rather than a failure.
      expect(
        MatrixState.isPangeaControllerInitialized,
        isFalse,
        reason: 'this case describes the pre-assignment window',
      );

      final client = await getTestClient(name: 'autosave-late-init');
      addTearDown(client.dispose);

      // The boot shape that reproduces it: logged in and already synced, so
      // neither await in start() suspends and the sweep runs inline.
      expect(
        client.prevBatch,
        isNotNull,
        reason: 'must not await a first sync',
      );

      final service = ActivityAutoSaveService(
        client: client,
        analyticsService: _FakeAnalyticsService(),
      );
      addTearDown(service.dispose);

      await expectLater(service.start(), completes);
    },
  );
}
