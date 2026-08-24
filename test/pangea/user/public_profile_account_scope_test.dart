// ignore_for_file: depend_on_referenced_packages

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

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// An account that is not the one [FakeMatrixApi] logs in as.
const _otherUserId = '@other:fakeServer.notExisting';

const _profileFieldRoute =
    '/client/unstable/uk.tcpip.msc4133/profile/'
    '%40test%3AfakeServer.notExisting/${PangeaEventTypes.profileAnalytics}';

/// [FakeMatrixApi] that records the body of every public-profile PUT — the
/// whole `pangea.analytics_profile` object, since the PUT replaces it wholesale
/// and whatever it omits is deleted server-side.
class _PublicProfileApi extends FakeMatrixApi {
  final List<Map<String, dynamic>> puts = [];

  @override
  FutureOr<http.Response> mockIntercept(http.Request request) async {
    if (request.method == 'PUT' &&
        request.url.path.endsWith(_profileFieldRoute)) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      puts.add(body[PangeaEventTypes.profileAnalytics] as Map<String, dynamic>);
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

/// #8531 — a public profile belongs to ONE account.
///
/// [UserController] lives for the life of the process while its client getter
/// resolves whichever account is active now, so a profile loaded for one login
/// must never be published under the next one — that is how a bio, a country
/// and another learner's analytics room ids landed on users who had set none of
/// them. See profile.instructions.md, "Ownership and mirroring".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late _PublicProfileApi api;
  late Client client;
  late PangeaController controller;

  /// Somebody else's profile: a filled-in bio and country, as the copied blobs
  /// carried them.
  PublicProfileModel foreignProfile() => PublicProfileModel(
    analytics: AnalyticsProfileModel(),
    about: 'WORDS EHRE I AM PUTTING TEXT IN THIS BOX',
    country: 'United States',
  );

  // [PangeaController]'s constructor boots the language store and the
  // subscription controller, so the plugins they reach for have to answer
  // before one can be built at all.
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('public_profile');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    // Seeded as already fetched, so the store reads these instead of going to
    // the network for the language list.
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
        ],
      }),
    });
    await PLanguageStore.initialize();
  });

  setUp(() async {
    api = _PublicProfileApi();
    api.api['GET']!['/.well-known/matrix/client'] = (_) => {};
    api.api['PUT']![_profileFieldRoute] = (_) => {};

    client = Client(
      'Public profile scope test',
      httpClient: api,
      database: await MatrixSdkDatabase.init(
        'test',
        // sqflite hands the same open instance back per path, so without this
        // every test would share one DB.
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

    controller = PangeaController(matrixState: _FakeMatrixState(client));
    MatrixState.pangeaController = controller;
  });

  test(
    'a profile loaded for another account is never published to this one',
    () async {
      controller.userController.setPublicProfile(
        foreignProfile(),
        userId: _otherUserId,
      );

      await controller.userController.updatePublicProfile();

      expect(api.puts, isEmpty);
      // Left as it was found rather than half-rewritten with this account's
      // settings — the blob still belongs to whoever it was loaded for.
      expect(controller.userController.publicProfile!.about, isNotNull);
    },
  );

  test(
    'logging out drops the profile, so the next login starts from nothing',
    () {
      controller.userController.setPublicProfile(
        foreignProfile(),
        userId: client.userID,
      );

      controller.userController.clear();

      // Null is what every writer gates on: "not loaded yet", never "loaded, for
      // somebody else".
      expect(controller.userController.publicProfile, isNull);
    },
  );

  test(
    'a bio and country left unset in settings are removed from the published profile',
    () async {
      // No account data at all: this account has set neither. The published
      // profile carries both, as a copied blob left it.
      controller.userController.setPublicProfile(
        foreignProfile(),
        userId: client.userID,
      );

      await controller.userController.updatePublicProfile();

      expect(api.puts, hasLength(1));
      expect(api.puts.single.containsKey(UserConstants.userAbout), isFalse);
      expect(api.puts.single.containsKey(UserConstants.userCountry), isFalse);
    },
  );

  test('a bio and country set in settings are published as they are', () async {
    client.accountData[UserConstants.userProfile] = BasicEvent(
      type: UserConstants.userProfile,
      content: {
        UserConstants.userSettings: {
          UserConstants.userAbout: 'Learning Spanish, say hi!',
          UserConstants.userCountry: 'Canada',
        },
      },
    );
    controller.userController.setPublicProfile(
      foreignProfile(),
      userId: client.userID,
    );

    await controller.userController.updatePublicProfile();

    expect(
      api.puts.single[UserConstants.userAbout],
      'Learning Spanish, say hi!',
    );
    expect(api.puts.single[UserConstants.userCountry], 'Canada');
  });

  test(
    'an analytics room id this user did not create is forgotten, its level kept',
    () {
      final spanish = LanguageModel(langCode: 'es', displayName: 'Spanish');
      final french = LanguageModel(langCode: 'fr', displayName: 'French');
      final analytics = AnalyticsProfileModel(
        languageAnalytics: {
          spanish: LanguageAnalyticsProfileEntry(
            4,
            0,
            analyticsRoomId: '!mine:fakeServer.notExisting',
          ),
          french: LanguageAnalyticsProfileEntry(
            7,
            0,
            analyticsRoomId: '!theirs:fakeServer.notExisting',
          ),
        },
      );

      analytics.clearForeignAnalyticsRoomIds({'!mine:fakeServer.notExisting'});

      expect(
        analytics.languageAnalytics![spanish]!.analyticsRoomId,
        '!mine:fakeServer.notExisting',
      );
      // Dropped: the instructor-access grant reads this id to pick the room it
      // invites instructors into, and a room the caller did not create is
      // refused — leaving that student's instructors with no access at all.
      expect(analytics.languageAnalytics![french]!.analyticsRoomId, isNull);
      // The level is not ours to judge here, so it stays.
      expect(analytics.languageAnalytics![french]!.level, 7);
    },
  );
}
