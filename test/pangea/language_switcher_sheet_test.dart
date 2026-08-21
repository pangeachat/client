import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' show BasicEvent, Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/svg_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_switcher_sheet.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_language_dropdown.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #8495 — the language switcher's row-level decisions
/// (profile.instructions.md, "Switching from context"): the current
/// language is marked and inert, the base language is refused and inert,
/// everything else is tappable. Deliberately doesn't tap a selectable row —
/// that starts UserController.updateTargetLanguage's real profile write,
/// which needs a fully-initialized client this test doesn't set up (see
/// user_controller_is_base_language_test.dart for that logic in isolation).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late L10n enL10n;
  late LanguageModel french;
  late LanguageModel spanish;
  late LanguageModel italian;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'language_switcher_sheet',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});

    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'fr',
            'language_name': 'French',
            'l2_support': 'full',
          },
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
          {
            'language_code': 'it',
            'language_name': 'Italian',
            'l2_support': 'full',
          },
        ],
      }),
    });
    await PLanguageStore.initialize();

    client = await prepareTestClient();
    french = PLanguageStore.byLangCode('fr')!;
    spanish = PLanguageStore.byLangCode('es')!;
    italian = PLanguageStore.byLangCode('it')!;
    enL10n = await lookupL10n(const Locale('en'));

    const flagSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>';
    await http.runWithClient(
      () => Future.wait([
        SvgRepo.get(french.svgUrl.toString()),
        SvgRepo.get(spanish.svgUrl.toString()),
        SvgRepo.get(italian.svgUrl.toString()),
      ]),
      () => MockClient((_) async => http.Response(flagSvg, 200)),
    );
  });

  tearDownAll(() => client.dispose());

  /// Seeds L1/L2 directly on the client's account-data cache and constructs
  /// a fresh controller — bypassing the network write entirely, since the
  /// sheet's build() only ever reads this synchronously.
  void seedController({
    required String base,
    required String target,
    Map<LanguageModel, LanguageAnalyticsProfileEntry>? languageAnalytics,
  }) {
    client.accountData[UserConstants.userProfile] = BasicEvent(
      type: UserConstants.userProfile,
      content: Profile(
        userSettings: UserSettings(
          sourceLanguage: base,
          targetLanguage: target,
        ),
      ).toJson(),
    );
    final controller = PangeaController(matrixState: _FakeMatrixState(client));
    controller.userController.setPublicProfile(
      PublicProfileModel(
        analytics: AnalyticsProfileModel(languageAnalytics: languageAnalytics),
      ),
    );
    MatrixState.pangeaController = controller;
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    LanguageModel? targetedLanguage,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: LanguageSwitcherSheet(targetedLanguage: targetedLanguage),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The row for [language] — its own InkWell, so tappability and the
  /// checkmark/label state can be asserted without ever invoking onTap.
  Finder rowFor(LanguageModel language) => find.ancestor(
    of: find.byWidgetPredicate(
      (w) => w is LanguageDropDownEntry && w.languageModel == language,
    ),
    matching: find.byType(InkWell),
  );

  /// Every language, top to bottom, the open sheet renders — mirrors
  /// p_language_dropdown_test.dart's helper of the same shape.
  List<LanguageModel> rowOrder(WidgetTester tester) => tester
      .widgetList<LanguageDropDownEntry>(find.byType(LanguageDropDownEntry))
      .map((entry) => entry.languageModel)
      .toList();

  testWidgets('the current language is checked and not tappable', (
    tester,
  ) async {
    seedController(
      base: 'en',
      target: 'fr',
      languageAnalytics: {french: LanguageAnalyticsProfileEntry(7, 0)},
    );
    await pumpSheet(tester);

    final row = tester.widget<InkWell>(rowFor(french));
    expect(row.onTap, isNull);
    expect(
      find.descendant(of: rowFor(french), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });

  testWidgets('the base language is refused, dimmed, and not tappable', (
    tester,
  ) async {
    seedController(base: 'es', target: 'fr');
    await pumpSheet(tester);

    final row = tester.widget<InkWell>(rowFor(spanish));
    expect(row.onTap, isNull);
    expect(
      find.descendant(
        of: rowFor(spanish),
        matching: find.text(enL10n.languageSwitcherBaseLanguageLabel),
      ),
      findsOneWidget,
    );
  });

  testWidgets('every other language is tappable', (tester) async {
    seedController(base: 'en', target: 'fr');
    await pumpSheet(tester);

    final row = tester.widget<InkWell>(rowFor(italian));
    expect(row.onTap, isNotNull);
  });

  testWidgets(
    'analytics languages lead with a level caption, above a divider',
    (tester) async {
      seedController(
        base: 'en',
        target: 'fr',
        languageAnalytics: {french: LanguageAnalyticsProfileEntry(7, 0)},
      );
      await pumpSheet(tester);

      expect(find.byType(Divider), findsOneWidget);
      expect(find.text(enL10n.languageDropdownLevel(7)), findsOneWidget);
    },
  );

  testWidgets('searching filters the list and drops the divider', (
    tester,
  ) async {
    seedController(
      base: 'en',
      target: 'fr',
      languageAnalytics: {french: LanguageAnalyticsProfileEntry(7, 0)},
    );
    await pumpSheet(tester);
    expect(find.byType(Divider), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ital');
    await tester.pumpAndSettle();

    expect(rowFor(italian), findsOneWidget);
    expect(rowFor(french), findsNothing);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('the targeted language leads, ahead of the analytics group', (
    tester,
  ) async {
    seedController(
      base: 'en',
      target: 'fr',
      languageAnalytics: {
        spanish: LanguageAnalyticsProfileEntry(4, 0),
        french: LanguageAnalyticsProfileEntry(7, 0),
      },
    );
    await pumpSheet(tester, targetedLanguage: italian);

    // Italian has no analytics of its own — it still leads, ahead of the
    // French/Spanish analytics group it doesn't belong to, and the
    // divider drops since nothing is left below it.
    expect(rowOrder(tester), [italian, french, spanish]);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets(
    'a targeted language already in the analytics group is not duplicated',
    (tester) async {
      seedController(
        base: 'en',
        target: 'fr',
        languageAnalytics: {
          spanish: LanguageAnalyticsProfileEntry(4, 0),
          french: LanguageAnalyticsProfileEntry(7, 0),
        },
      );
      await pumpSheet(tester, targetedLanguage: spanish);

      expect(rowOrder(tester), [spanish, french, italian]);
      expect(find.byType(Divider), findsOneWidget);
    },
  );
}
