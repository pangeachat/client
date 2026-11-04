import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/locale_provider.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/svg_repo.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/pick_language_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_tiles.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_language_dropdown.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #9410 — the app's menus follow the base language, so a new base language
/// that would switch them waits for the learner to confirm it, in learning
/// settings and on the onboarding language step. Nothing changes until they
/// tap Change, and nothing asks while the menus would stay as they are.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late MatrixState matrixState;
  late L10n l10n;
  late LanguageModel spanish;
  late LanguageModel french;

  setUpAll(() async {
    // Avatar and the language rows read BotName.byEnvironment and fetch flag
    // SVGs, which need GetStorage (path_provider-backed) and dotenv.
    final tempDir = await Directory.systemTemp.createTemp(
      'base_language_change',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    await GetStorage.init('svg_cache');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});

    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'en',
            'language_name': 'English',
            'l2_support': 'full',
          },
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
          {
            'language_code': 'fr',
            'language_name': 'French',
            'l2_support': 'full',
          },
          {
            'language_code': 'de',
            'language_name': 'German',
            'l2_support': 'full',
          },
        ],
      }),
    });
    await PLanguageStore.initialize();

    client = await prepareTestClient();
    matrixState = _FakeMatrixState(client);
    MatrixState.pangeaController = PangeaController(matrixState: matrixState);

    // Loading a translation is real async work, which a test body's fake
    // clock never runs, and the immersion tile loads the base language's.
    l10n = await lookupL10n(const Locale('en'));
    for (final code in ['es', 'fr', 'de']) {
      await lookupL10n(Locale(code));
    }

    spanish = PLanguageStore.byLangCode('es')!;
    french = PLanguageStore.byLangCode('fr')!;

    // Warm SvgRepo on the real clock, so no row waits on a flag fetch.
    const flagSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>';
    await http.runWithClient(
      () => Future.wait([
        for (final code in ['en', 'es', 'fr', 'de'])
          SvgRepo.get(PLanguageStore.byLangCode(code)!.svgUrl.toString()),
      ]),
      () => MockClient((_) async => http.Response(flagSvg, 200)),
    );
  });

  tearDownAll(() => client.dispose());

  /// Opens [dropdown] and picks [language] from its menu.
  Future<void> pick(
    WidgetTester tester,
    Finder dropdown,
    LanguageModel language,
  ) async {
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // The menu item's ink well takes the tap, not the row inside it.
    await tester.tap(
      find
          .ancestor(
            of: find
                .byWidgetPredicate(
                  (w) =>
                      w is LanguageDropDownEntry && w.languageModel == language,
                )
                .last,
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  Finder confirmation() => find.text(l10n.changeBaseLanguageTitle);

  group('learning settings', () {
    late int saves;

    LearningSettingsViewModel makeViewModel({
      required bool appLanguageIsTarget,
    }) {
      saves = 0;
      return LearningSettingsViewModel(
        Profile(
          userSettings: UserSettings(
            sourceLanguage: 'es',
            targetLanguage: 'de',
            appLanguageIsTarget: appLanguageIsTarget,
          ),
        ),
        onUpdateProfile: () => saves++,
      );
    }

    Future<LearningSettingsViewModel> pumpSettings(
      WidgetTester tester, {
      bool appLanguageIsTarget = false,
    }) async {
      final viewModel = makeViewModel(appLanguageIsTarget: appLanguageIsTarget);
      final languageError = ValueNotifier<String?>(null);
      addTearDown(viewModel.dispose);
      addTearDown(languageError.dispose);

      await tester.pumpWidget(
        Provider<MatrixState>.value(
          value: matrixState,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: LearningSettingsTiles(
                  viewModel: viewModel,
                  languageErrorNotifier: languageError,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return viewModel;
    }

    // The base language is the first of the page's two language dropdowns.
    Finder baseLanguageDropdown() =>
        find.byType(DropdownButtonFormField2<LanguageModel>).first;

    testWidgets('a new base language waits for Change', (tester) async {
      final viewModel = await pumpSettings(tester);

      await pick(tester, baseLanguageDropdown(), french);

      expect(confirmation(), findsOneWidget);
      expect(
        find.text(l10n.changeBaseLanguageDesc(french.getDisplayName(l10n))),
        findsOneWidget,
      );
      expect(viewModel.selectedSourceLanguage?.langCode, spanish.langCode);
      expect(saves, 0);

      await tester.tap(find.text(l10n.change));
      await tester.pumpAndSettle();

      expect(confirmation(), findsNothing);
      expect(viewModel.selectedSourceLanguage?.langCode, french.langCode);
      expect(saves, 1);
    });

    testWidgets('Cancel leaves the base language as it was', (tester) async {
      final viewModel = await pumpSettings(tester);

      await pick(tester, baseLanguageDropdown(), french);
      expect(confirmation(), findsOneWidget);

      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      expect(confirmation(), findsNothing);
      expect(viewModel.selectedSourceLanguage?.langCode, spanish.langCode);
      expect(saves, 0);
      // The dropdown holds the language it had, not the declined pick.
      expect(
        tester
            .state<FormFieldState<LanguageModel>>(baseLanguageDropdown())
            .value
            ?.langCode,
        spanish.langCode,
      );
    });

    testWidgets('asks only while the menus follow the base language', (
      tester,
    ) async {
      final viewModel = await pumpSettings(tester, appLanguageIsTarget: true);

      // The menus stay in the target language, so the change is made at once.
      await pick(tester, baseLanguageDropdown(), french);

      expect(confirmation(), findsNothing);
      expect(viewModel.selectedSourceLanguage?.langCode, french.langCode);
      expect(saves, 1);

      // Once the app is back in the base language, the next change asks.
      viewModel.setAppLanguageIsTarget(false);
      await tester.pumpAndSettle();
      await pick(tester, baseLanguageDropdown(), spanish);

      expect(confirmation(), findsOneWidget);
      expect(viewModel.selectedSourceLanguage?.langCode, french.langCode);
    });
  });

  group('onboarding language step', () {
    late LocaleProvider localeProvider;
    late OnboardingStateController state;

    /// Pumps the step and learns the language it took as the learner's own,
    /// which is what brings up its base-language dropdown.
    Future<void> pumpStepWithIdenticalLanguages(WidgetTester tester) async {
      localeProvider = LocaleProvider();
      addTearDown(localeProvider.dispose);
      state = OnboardingStateController(
        accountUpdater: MockAccountUpdater(),
        courseProvider: MockCourseProvider(),
        avatarProvider: MockAvatarProvider(),
        trialInfoProvider: MockTrialInfoProvider(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: localeProvider,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: PickLanguageStepView(
                step: PickLanguageOnboardingStep(
                  client: client,
                  state: state,
                  maxRemainingSteps: 2,
                ),
                loading: false,
                error: null,
                hasNextStep: true,
                forward: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The step switches the app language 500 ms after its base language
      // changes, the entry seed included.
      await tester.pump(const Duration(milliseconds: 600));

      final seed = state.baseLanguage!;
      expect(localeProvider.locale?.languageCode, seed.langCodeShort);

      await tester.tap(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.text(seed.getDisplayName(l10n)),
        ),
      );
      await tester.pumpAndSettle();
    }

    LanguageModel newBaseLanguage() =>
        state.baseLanguage == french ? spanish : french;

    testWidgets('asks before the app language switches, and switches it on '
        'Change', (tester) async {
      await pumpStepWithIdenticalLanguages(tester);
      final seed = state.baseLanguage!;
      final picked = newBaseLanguage();

      await pick(
        tester,
        find.byType(DropdownButtonFormField2<LanguageModel>),
        picked,
      );

      expect(confirmation(), findsOneWidget);
      expect(
        find.text(l10n.changeBaseLanguageDesc(picked.getDisplayName(l10n))),
        findsOneWidget,
      );
      // Nothing switches while the learner decides.
      await tester.pump(const Duration(milliseconds: 600));
      expect(state.baseLanguage?.langCode, seed.langCode);
      expect(localeProvider.locale?.languageCode, seed.langCodeShort);

      await tester.tap(find.text(l10n.change));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));

      expect(state.baseLanguage?.langCode, picked.langCode);
      expect(localeProvider.locale?.languageCode, picked.langCodeShort);
    });

    testWidgets('Cancel keeps the base language and the app language', (
      tester,
    ) async {
      await pumpStepWithIdenticalLanguages(tester);
      final seed = state.baseLanguage!;

      await pick(
        tester,
        find.byType(DropdownButtonFormField2<LanguageModel>),
        newBaseLanguage(),
      );
      expect(confirmation(), findsOneWidget);

      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));

      expect(confirmation(), findsNothing);
      expect(state.baseLanguage?.langCode, seed.langCode);
      expect(localeProvider.locale?.languageCode, seed.langCodeShort);
    });
  });
}
