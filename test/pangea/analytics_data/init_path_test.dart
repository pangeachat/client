import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_model.dart' as pangea;
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'analytics_fixtures.dart';

const _profileFieldRoute =
    '/client/unstable/uk.tcpip.msc4133/profile/'
    '%40test%3AfakeServer.notExisting/${PangeaEventTypes.profileAnalytics}';

/// Holds every public-profile PUT open until released, so a test can have one
/// genuinely stalled — not failed — while init runs.
class _GatedProfileApi extends FakeMatrixApi {
  Completer<void>? gate;
  final List<Map<String, dynamic>> puts = [];

  @override
  FutureOr<http.Response> mockIntercept(http.Request request) async {
    if (request.method == 'PUT' &&
        request.url.path.endsWith(_profileFieldRoute)) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      puts.add(body[PangeaEventTypes.profileAnalytics] as Map<String, dynamic>);
      if (gate != null) await gate!.future;
    }
    return super.mockIntercept(request);
  }
}

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
///
/// Nothing on the init path publishes any more, so the stalled-publish test
/// below passes today no matter what. It is kept as a guard: it fails the
/// moment anything on that path starts awaiting a profile write again, which
/// has now happened twice.
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
    // shared preferences on construction. Seeded as already fetched so the
    // learner's target language resolves to a model rather than null.
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': testLang,
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
          {'language_code': 'en', 'language_name': 'English'},
        ],
      }),
    });
    await PLanguageStore.initialize();
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

  var storeSeq = 0;

  /// A LOGGED-IN service, so `_initAnalytics` actually runs. The other tests
  /// here reach the state init runs in; this drives init itself, which is the
  /// only way to see anything init awaits.
  Future<(AnalyticsDataService, _GatedProfileApi)> loggedInService() async {
    // A distinct store per call — a shared one carries the previous test's seed.
    final storeName = 'analytics_init_${storeSeq++}';

    final api = _GatedProfileApi();
    api.api['GET']!['/.well-known/matrix/client'] = (_) => {};
    api.api['PUT']![_profileFieldRoute] = (_) => {};

    final client = Client(
      'testclient',
      httpClient: api,
      database: await MatrixSdkDatabase.init(
        'init_path_logged_in',
        database: await databaseFactoryFfi.openDatabase(
          ':memory:',
          options: OpenDatabaseOptions(singleInstance: false),
        ),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    await client.checkHomeserver(Uri.parse('https://fakeserver.notexisting'));
    await client.login(
      LoginType.mLoginToken,
      identifier: AuthenticationUserIdentifier(user: 'test'),
      password: '1234',
    );

    client.accountData[UserConstants.userProfile] = BasicEvent(
      type: UserConstants.userProfile,
      content: pangea.Profile(
        userSettings: pangea.UserSettings(
          sourceLanguage: 'en',
          targetLanguage: testLang,
        ),
      ).toJson(),
    );

    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
    MatrixState.pangeaController.userController.setPublicProfile(
      PublicProfileModel(analytics: AnalyticsProfileModel()),
      userId: client.userID,
    );

    final db = await freshDatabase(name: storeName);
    await db.updateUserID(client.userID!);
    // A current language must be set or init treats the store as
    // uninitialized and hard-refreshes it.
    await db.updateCurrentLanguage(testLang);

    return (
      AnalyticsDataService(client, databaseBuilder: (_) async => db),
      api,
    );
  }

  test('init completes even while another profile publish is stalled', () async {
    // Profile publishes are serialized behind one chain and the Matrix profile
    // PUT has no timeout, so anything init AWAITS that ends in a publish parks
    // init behind whatever else is publishing — and UserController.initialize
    // fires one off un-awaited on every startup. Awaiting reconciliation here
    // hung initialization outright, with initError null and no error state:
    // the #8592 failure reached through a different door.
    final (service, api) = await loggedInService();
    api.gate = Completer<void>();

    // Somebody else's publish, in flight and going nowhere.
    unawaited(
      MatrixState.pangeaController.userController.updateAnalyticsProfile(
        languageCode: testLang,
        level: 2,
      ),
    );

    await service.initCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail(
        'analytics init hung behind a stalled profile publish: something on '
        'the init path is awaiting a network write',
      ),
    );

    expect(service.initError, isNull);
    api.gate!.complete();
  });

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
