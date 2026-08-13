import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/app_language_settings_tile.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #8353 — the immersion toggle ("show the app in the language I'm learning")
/// keeps its own copy in the learner's base language, so a learner who turned
/// it on and can't read the target language yet can still find it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late L10n esL10n;
  late L10n deL10n;
  late L10n enL10n;

  setUpAll(() async {
    // The base language resolves through PLanguageStore, so seed its cache
    // rather than letting initialize() reach the network. `zz` stands in for a
    // language the app has no translation for.
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
          {'language_code': 'de', 'language_name': 'German'},
          {'language_code': 'zz', 'language_name': 'Nowhereish'},
        ],
      }),
    });
    await PLanguageStore.initialize();

    // The view model listens to the user controller's profile streams, so it
    // needs a controller to reach through MatrixState.
    client = await prepareTestClient();
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );

    // Loading a translation is real async work (deferred libraries), so it
    // can't happen inside a test body's fake clock — resolve them up front.
    esL10n = await lookupL10n(const Locale('es'));
    deL10n = await lookupL10n(const Locale('de'));
    enL10n = await lookupL10n(const Locale('en'));
  });

  tearDownAll(() => client.dispose());

  LearningSettingsViewModel makeViewModel({
    String? sourceLanguage = 'es',
    bool appLanguageIsTarget = true,
  }) => LearningSettingsViewModel(
    Profile(
      userSettings: UserSettings(
        sourceLanguage: sourceLanguage,
        targetLanguage: 'de',
        appLanguageIsTarget: appLanguageIsTarget,
      ),
    ),
  );

  /// The tile resolves its base-language copy through a future, so it takes an
  /// extra frame to appear. (Every locale this file asserts on is loaded in
  /// `setUpAll` — a translation this isolate hasn't loaded yet needs real
  /// async, which a test body's fake clock never gets to.)
  Future<void> settleBaseLanguageLoad(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  }

  /// The app itself is in English here — what the tile renders is the base
  /// language's copy, not the app's.
  Future<void> pumpTile(
    WidgetTester tester,
    LearningSettingsViewModel viewModel,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) =>
                AppLanguageSettingsTile(viewModel: viewModel),
          ),
        ),
      ),
    );
    await settleBaseLanguageLoad(tester);
  }

  testWidgets('renders its copy in the base language, not the app language', (
    tester,
  ) async {
    await pumpTile(tester, makeViewModel());

    expect(find.text(esL10n.appInTargetLanguageTitle), findsOneWidget);
    expect(find.textContaining(esL10n.appInTargetLanguageDesc), findsOneWidget);
    expect(find.text(enL10n.appInTargetLanguageTitle), findsNothing);
  });

  testWidgets('explains that it stays in the base language while immersion is '
      'on, and drops the note when it is off', (tester) async {
    final viewModel = makeViewModel();
    await pumpTile(tester, viewModel);

    expect(
      find.textContaining(esL10n.appInTargetLanguageStaysInBaseLanguage),
      findsOneWidget,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(viewModel.appLanguageIsTarget, isFalse);
    expect(
      find.textContaining(esL10n.appInTargetLanguageStaysInBaseLanguage),
      findsNothing,
    );
  });

  testWidgets('follows the base language dropdown on the same page', (
    tester,
  ) async {
    final viewModel = makeViewModel();
    await pumpTile(tester, viewModel);

    expect(find.text(esL10n.appInTargetLanguageTitle), findsOneWidget);

    viewModel.setSelectedLanguage(
      sourceLanguage: PLanguageStore.byLangCode('de'),
    );
    await tester.pump();
    await settleBaseLanguageLoad(tester);

    expect(find.text(deL10n.appInTargetLanguageTitle), findsOneWidget);
  });

  testWidgets('falls back to the app copy for an untranslated base language', (
    tester,
  ) async {
    await pumpTile(tester, makeViewModel(sourceLanguage: 'zz'));

    expect(find.text(enL10n.appInTargetLanguageTitle), findsOneWidget);
  });
}
