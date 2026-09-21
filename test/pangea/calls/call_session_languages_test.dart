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

import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// pangeachat/.github#410 — whose language a call transcript half is
/// transcribed against.
///
/// A call has no language of its own. It has two HALVES, each recorded from one
/// device's own microphone, published under one account, and credited to that
/// account's own analytics. The language pair is one more per-half property and
/// belongs to the account that publishes the half — `room.client`, the same
/// client `startCall` already resolves the call service and the analytics sink
/// from, and the same client the half is stamped with as its `sender_id`.
///
/// It was the one thing in `startCall` still read through
/// `pangeaController.userController`, whose `client` getter resolves whichever
/// account is FOREGROUNDED. That is not a cosmetic mismatch: server-side the
/// target language selects the whole provider fallback chain and arms a
/// script-mismatch guard that discards anything in the wrong script, so the
/// wrong pair does not return an approximation — it returns nothing.
///
/// [UserController.languageCodesFor] is the fix. It takes the client EXPLICITLY
/// and reads that client's own account data, never consulting or populating the
/// process-wide controller's cache, and never writing.
class _AccountDataApi extends FakeMatrixApi {
  /// Every account-data write this client made, by account-data type.
  final List<String> accountDataPuts = [];

  @override
  FutureOr<http.Response> mockIntercept(http.Request request) async {
    if (request.method == 'PUT' &&
        request.url.path.contains('/account_data/')) {
      accountDataPuts.add(request.url.path.split('/account_data/').last);
    }
    return super.mockIntercept(request);
  }
}

/// Where `Profile.saveProfileData` writes: the signed-in account's `profile`
/// account-data key.
const _accountDataRoute =
    '/client/v3/user/%40test%3AfakeServer.notExisting/account_data/'
    '${UserConstants.userProfile}';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  /// Writes a profile in the CURRENT account-data format: one `profile` blob
  /// holding a `user_settings` map.
  void setLanguages(Client client, {String? l1, required String? l2}) {
    client.accountData[UserConstants.userProfile] = BasicEvent(
      type: UserConstants.userProfile,
      content: {
        UserConstants.userSettings: {
          ModelKey.sourceLanguage: ?l1,
          ModelKey.targetLanguage: ?l2,
        },
      },
    );
  }

  /// Writes the OLD, pre-migration shape: the languages live in their own
  /// top-level account-data events rather than inside a `profile` blob.
  /// `UserSettings.migrateFromAccountData` only reads this path when a date of
  /// birth is present, so one is written too.
  void setLegacyLanguages(
    Client client, {
    required String l1,
    required String l2,
  }) {
    client.accountData[UserConstants.userDateOfBirth] = BasicEvent(
      type: UserConstants.userDateOfBirth,
      content: {UserConstants.userDateOfBirth: '2000-01-01T00:00:00.000Z'},
    );
    client.accountData[ModelKey.sourceLanguage] = BasicEvent(
      type: ModelKey.sourceLanguage,
      content: {ModelKey.sourceLanguage: l1},
    );
    client.accountData[ModelKey.targetLanguage] = BasicEvent(
      type: ModelKey.targetLanguage,
      content: {ModelKey.targetLanguage: l2},
    );
  }

  late _AccountDataApi api;

  Future<Client> account(String name) async {
    final client = Client(
      name,
      httpClient: api,
      database: await MatrixSdkDatabase.init(
        'test',
        // sqflite hands the same open instance back per path, so without this
        // the two accounts in a test would share one database.
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
    addTearDown(client.dispose);
    return client;
  }

  // [PangeaController]'s constructor boots the language store and the
  // subscription controller, so the plugins they reach for have to answer
  // before one can be built at all.
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('call_languages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
    // Seeded as already fetched, so the store reads these instead of going to
    // the network for the language list. `en` is here because the L1 fallback
    // resolves the DEVICE's system language through this store.
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          for (final code in ['en', 'es', 'pt', 'it', 'ja', 'ko', 'hi'])
            {
              'language_code': code,
              'language_name': code,
              'l2_support': 'full',
            },
        ],
      }),
    });
    await PLanguageStore.initialize();
  });

  setUp(() {
    api = _AccountDataApi();
    api.api['GET']!['/.well-known/matrix/client'] = (_) => {};
    // The account-data PUT the legacy migration makes. Registered so the
    // positive control in the write test can actually SUCCEED; without it the
    // fake answers M_UNRECOGNIZED and the control proves only that the route
    // is unmocked.
    api.api['PUT']![_accountDataRoute] = (_) => {};
  });

  test(
    'reads an account\'s own languages from the current profile format',
    () async {
      final client = await account('one account');
      setLanguages(client, l1: 'pt', l2: 'it');

      final languages = UserController.languageCodesFor(client);

      expect(languages.l1, 'pt');
      expect(languages.l2, 'it');
    },
  );

  test('reads them from the legacy, pre-migration format too', () async {
    final client = await account('legacy account');
    setLegacyLanguages(client, l1: 'ja', l2: 'ko');

    final languages = UserController.languageCodesFor(client);

    expect(languages.l1, 'ja');
    expect(languages.l2, 'ko');
  });

  test(
    'the FOREGROUNDED account\'s languages never reach another account\'s call',
    () async {
      // The account that happens to be active when the call starts. It is
      // wired up for real -- as the controller's `client` -- so that a
      // resolver which quietly consulted the singleton would ANSWER with these
      // rather than throw, and the test would still catch it.
      final foreground = await account('foreground');
      setLanguages(foreground, l1: 'en', l2: 'hi');
      MatrixState.pangeaController = PangeaController(
        matrixState: _FakeMatrixState(foreground),
      );

      // The account that actually owns the room the call is in, and that will
      // publish the half.
      final callAccount = await account('call account');
      setLanguages(callAccount, l1: 'pt', l2: 'it');

      final languages = UserController.languageCodesFor(callAccount);

      expect(
        languages.l2,
        'it',
        reason:
            'the target language decides the provider chain; taking it from '
            'the foregrounded account is pangeachat/.github#410',
      );
      expect(languages.l1, 'pt');

      // And the singleton is left exactly as it was: still answering for the
      // account that is foregrounded, its cache neither read nor filled with
      // somebody else's profile.
      expect(
        MatrixState.pangeaController.userController.userL2Code,
        'hi',
        reason: 'resolving for one account must not re-point the singleton',
      );
    },
  );

  test('an unset target language is never filled in from anywhere', () async {
    final foreground = await account('foreground with languages');
    // `ko` rather than `en` on purpose: the L1 fallback below resolves the
    // HOST's locale, and on an `en` host an `en` foreground L1 would make the
    // two indistinguishable and the assertion vacuous.
    setLanguages(foreground, l1: 'ko', l2: 'hi');
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(foreground),
    );

    // An account that has set neither language: a fresh signup, or one whose
    // profile has not synced yet.
    final unset = await account('unset account');
    setLanguages(unset, l1: null, l2: null);

    final languages = UserController.languageCodesFor(unset);

    // L2 has no fallback at all. Null here becomes `unk` at the call site,
    // which choreo reads as "no stated target"; borrowing the other account's
    // `hi` would send this learner's speech down a Hindi provider chain.
    expect(languages.l2, isNull);
    // L1 keeps the one fallback `userL1Code` has always had, and it is the
    // DEVICE's system language -- device state, not another account's state.
    expect(languages.l1, LanguageService.systemLanguage?.langCode);
    expect(
      languages.l1,
      isNot('ko'),
      reason: 'the fallback is the device locale, never another account\'s L1',
    );
  });

  test('resolving an account\'s languages writes to no account', () async {
    // A legacy-format account is the case that matters: reading it through
    // `UserController.profile` MIGRATES it and saves the migrated blob, and
    // that save lands on whichever account is foregrounded.
    final foreground = await account('foreground');
    setLegacyLanguages(foreground, l1: 'en', l2: 'hi');
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(foreground),
    );

    // Positive control, so the assertion below cannot pass vacuously: the
    // path this replaces really does write.
    MatrixState.pangeaController.userController.profile;
    await pumpEventQueue();
    expect(
      api.accountDataPuts,
      contains(UserConstants.userProfile),
      reason:
          'if reading a legacy profile no longer writes, the control below '
          'proves nothing and this test must be rewritten',
    );

    api.accountDataPuts.clear();

    final callAccount = await account('call account');
    setLegacyLanguages(callAccount, l1: 'pt', l2: 'it');

    final languages = UserController.languageCodesFor(callAccount);
    await pumpEventQueue();

    expect(languages.l2, 'it');
    expect(
      api.accountDataPuts,
      isEmpty,
      reason:
          'placing a call is not a settings edit; it must not write to any '
          'account, least of all the foregrounded one it does not own',
    );
  });

  test(
    'a call binds its languages to the room\'s client, not the active one',
    () {
      // Structural pin, matching this suite's own convention for wiring facts
      // that are cheap to assert on the source and expensive to exercise through
      // a full widget tree (`incoming_call_banner_test.dart` greps `_listen` the
      // same way). What it pins is the invariant: inside `startCall`, the ONE
      // client the languages are resolved from is `room.client` -- the same
      // client the half is published and stamped by.
      final source = File('lib/widgets/matrix.dart').readAsStringSync();
      final start = source.indexOf('void startCall(');
      expect(start, greaterThan(-1), reason: 'startCall must still exist');
      final end = source.indexOf('\n  }\n  // Pangea#', start);
      expect(end, greaterThan(start));
      final body = source.substring(start, end);

      expect(
        body.contains('UserController.languageCodesFor(room.client)'),
        isTrue,
        reason:
            'the languages must be resolved from the room\'s OWN client, never '
            'the foregrounded account',
      );
      expect(
        body.contains('.userController.userL1Code') ||
            body.contains('.userController.userL2Code'),
        isFalse,
        reason:
            'reading the languages through the active-account userController '
            'here is exactly the bug (pangeachat/.github#410)',
      );
    },
  );
}
