import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/locale_provider.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

/// Skips `initState` (and `initMatrix()`) the same way
/// `matrix_state_login_race_test.dart` does — none of what it wires is read
/// here, and none of it stands up under `flutter test`.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// Serves a fixed profile so the locale can be resolved without a synced
/// account.
class _FixedProfileUserController extends UserController {
  _FixedProfileUserController(this._profile);

  final Profile _profile;

  @override
  Profile get profile => _profile;
}

/// #8509 — "show the app in the language I'm learning" had no effect on login.
///
/// `setAppLanguage` is the single resolver for the app UI locale
/// (localization.instructions.md, "Which language the app UI uses"). It is
/// public precisely so `PangeaController._onLogin` can re-apply it once the
/// new account's profile has loaded: every other call site runs at app start,
/// and neither profile stream emits on login, so without that call a
/// logout/login leaves the locale on the null `_onLogout` set — which renders
/// the device language, not the learner's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // `LocaleProvider` validates a language against intl's date-locale data,
    // which is uninitialized until a frame with the localization delegates has
    // been built — and throws, not returns false, until then. A real app is
    // past that by the time `setAppLanguage` runs (it is called from
    // post-frame callbacks and stream listeners); load the data here so this
    // test is too. Mirrors `locale_provider_test.dart`.
    initializeDateFormatting();
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeserver.notexisting'},
    );
    final tempDir = await Directory.systemTemp.createTemp('matrix_state_lang');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    client = await prepareTestClient();
  });

  tearDownAll(() async {
    await client.dispose();
  });

  /// Pumps [Matrix] under a [LocaleProvider] and points its controller at a
  /// profile carrying [settings]. Returns the state and the provider the app
  /// reads its locale from.
  Future<(MatrixState, LocaleProvider)> pumpWithSettings(
    WidgetTester tester,
    UserSettings settings,
  ) async {
    final localeProvider = LocaleProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<LocaleProvider>.value(
        value: localeProvider,
        child: _TestMatrix(
          clients: <Client>[client],
          store: store,
          child: const SizedBox(),
        ),
      ),
    );
    final state = tester.state<_TestMatrixState>(find.byType(_TestMatrix));
    MatrixState.pangeaController = PangeaController(matrixState: state);
    MatrixState.pangeaController.userController = _FixedProfileUserController(
      Profile(userSettings: settings),
    );
    return (state, localeProvider);
  }

  testWidgets('resolves the target language when the toggle is on', (
    tester,
  ) async {
    final (state, provider) = await pumpWithSettings(
      tester,
      UserSettings(
        sourceLanguage: 'en',
        targetLanguage: 'de',
        appLanguageIsTarget: true,
      ),
    );

    state.setAppLanguage();

    expect(provider.locale, const Locale('de'));
  });

  testWidgets('resolves the source language when the toggle is off', (
    tester,
  ) async {
    final (state, provider) = await pumpWithSettings(
      tester,
      UserSettings(sourceLanguage: 'en', targetLanguage: 'de'),
    );

    state.setAppLanguage();

    expect(provider.locale, const Locale('en'));
  });

  testWidgets('falls back to the source language when no target is set', (
    tester,
  ) async {
    final (state, provider) = await pumpWithSettings(
      tester,
      UserSettings(sourceLanguage: 'en', appLanguageIsTarget: true),
    );

    state.setAppLanguage();

    expect(provider.locale, const Locale('en'));
  });

  testWidgets('re-applies the locale that logout cleared', (tester) async {
    final (state, provider) = await pumpWithSettings(
      tester,
      UserSettings(
        sourceLanguage: 'en',
        targetLanguage: 'de',
        appLanguageIsTarget: true,
      ),
    );

    // What `PangeaController._onLogout` leaves behind. Until #8509 nothing on
    // the login path put a locale back, so the app rendered in the device
    // language for the rest of the session.
    provider.setLocale(null);
    expect(provider.locale, isNull);

    // What `_onLogin` now does once the new account's profile has loaded.
    state.setAppLanguage();

    expect(provider.locale, const Locale('de'));
  });
}
