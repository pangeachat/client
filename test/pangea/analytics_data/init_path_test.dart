import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'analytics_fixtures.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);
  final Client _client;
  @override
  Client get client => _client;
}

/// The analytics INIT path — the one path in this service that runs before
/// `initCompleter` completes, and the one nothing could reach from a test.
///
/// #8592 put a read on it that awaited `initCompleter` itself, so
/// initialization waited on its own completion: analytics never finished
/// starting, every read gated on the same completer hung behind it, and the UI
/// sat on its loading state with no error and no Sentry event. The whole suite
/// stayed green throughout, because no test constructs a real
/// [AnalyticsDataService]. These tests exist so that class of defect fails
/// here instead of on a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('analytics_init');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    // PangeaController builds a PLanguageStore, which reads its cache from
    // shared preferences on construction.
    SharedPreferences.setMockInitialValues({});
  });

  /// A client that is NOT logged in, so `_initDatabase` opens the store and
  /// then parks waiting for login. That is exactly the state the init path
  /// runs in: store ready, `initCompleter` still open.
  Future<AnalyticsDataService> serviceMidInit() async {
    final client = Client(
      'testclient',
      httpClient: FakeMatrixApi(),
      database: await MatrixSdkDatabase.init(
        'init_path_test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );

    final db = await freshDatabase();
    final service = AnalyticsDataService(
      client,
      databaseBuilder: (_) async => db,
    );
    await service.databaseReady.future;
    return service;
  }

  test(
    'a server-analytics update completes while init is still in flight',
    () async {
      final service = await serviceMidInit();
      expect(
        service.isInitializing,
        isTrue,
        reason: 'the test must reach the state the init path actually runs in',
      );

      // bulkUpdate lands here from inside _initAnalytics whenever the analytics
      // room holds events the local store does not — the ordinary returning-user
      // and multi-device case, and every language switch. If anything it calls
      // waits on initCompleter, this never returns.
      await service
          .updateServerAnalytics([], testLang)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail(
              'updateServerAnalytics hung: something on the init path is '
              'waiting for init to finish',
            ),
          );

      expect(service.isInitializing, isTrue);
    },
  );

  test(
    'reconciling published levels completes while init is in flight',
    () async {
      final service = await serviceMidInit();

      await service.updateXPOffset(900, testLang);
      await service.reconcilePublishedLevels().timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail(
          'reconcilePublishedLevels hung: it runs inside init, so it must '
          'not read through anything that waits for init to finish',
        ),
      );

      expect(service.isInitializing, isTrue);
    },
  );

  test('the recomputed level is published without waiting for init', () async {
    final service = await serviceMidInit();

    // Same call, with a language whose stored total is non-zero, so the level
    // publication actually runs rather than short-circuiting on empty data.
    await service.updateXPOffset(600, testLang);
    await service
        .updateServerAnalytics([], testLang)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('level publication hung on the init path'),
        );

    expect(service.isInitializing, isTrue);
  });
}
