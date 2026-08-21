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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_flag_chip.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/svg_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_language_dropdown.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #8495 — languages the learner already has analytics in sort to the top
/// of the target-language dropdown, so the two or three they actually move
/// between are reachable without scrolling or searching
/// (profile.instructions.md, "Switching from context"). The base-language
/// dropdown is untouched, and a learner with no analytics yet sees today's
/// plain alphabetical list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late L10n enL10n;
  late LanguageModel french;
  late LanguageModel spanish;
  late LanguageModel spanishMexico;
  late LanguageModel italian;

  setUpAll(() async {
    // Avatar and LanguageFlagChip read BotName.byEnvironment / fetch flag
    // SVGs, which need GetStorage (path_provider-backed) and dotenv readable.
    final tempDir = await Directory.systemTemp.createTemp(
      'p_language_dropdown',
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
          // Gives plain Spanish a localized sibling, so
          // LanguageModel.shouldShowFlag is false for it (#8495 review — an
          // analytics row with no usable flag must keep Avatar's circle
          // rather than falling to LanguageFlagChip's cramped two-letter
          // code badge).
          {
            'language_code': 'es-MX',
            'language_name': 'Spanish (Mexico)',
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
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );

    enL10n = await lookupL10n(const Locale('en'));
    french = PLanguageStore.byLangCode('fr')!;
    spanish = PLanguageStore.byLangCode('es')!;
    spanishMexico = PLanguageStore.byLangCode('es-MX')!;
    italian = PLanguageStore.byLangCode('it')!;

    // Every row whose language shows a flag renders it inline
    // (LanguageDisplayNamePostfixWidget / LanguageFlagChip), each an
    // NetworkSvg fetch. SvgRepo memoizes by URL for the session, so warming
    // it here — on setUpAll's real event loop, not a testWidgets body's fake
    // clock — means the widget tests below never wait on a real fetch: the
    // loading placeholder (an indeterminate spinner pumpAndSettle can never
    // wait out) flips to resolved on the very next pump.
    const flagSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>';
    await http.runWithClient(
      () => Future.wait([
        SvgRepo.get(french.svgUrl.toString()),
        SvgRepo.get(spanishMexico.svgUrl.toString()),
        SvgRepo.get(italian.svgUrl.toString()),
      ]),
      () => MockClient((_) async => http.Response(flagSvg, 200)),
    );
  });

  tearDownAll(() => client.dispose());

  setUp(() {
    // Each test starts from no analytics; individual tests opt in.
    MatrixState.pangeaController.userController.setPublicProfile(null);
  });

  /// Builds the dropdown and opens its menu. Every flag it needs is already
  /// in SvgRepo's cache from setUpAll, so this is a plain pump — no network
  /// wait for pumpAndSettle to hang on.
  Future<void> openDropdown(WidgetTester tester, {bool isL2List = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: PLanguageDropdown(
            languages: isL2List
                ? MatrixState.pangeaController.pLanguageStore.targetOptions
                : MatrixState.pangeaController.pLanguageStore.baseOptions,
            onChange: (_) {},
            initialLanguage: null,
            isL2List: isL2List,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField2<LanguageModel>));
    await tester.pumpAndSettle();
  }

  /// Every language, top to bottom, the open menu renders — read off
  /// [LanguageDropDownEntry] directly rather than its text (the display name
  /// renders as a RichText, not a Text, so it can't be found the same way).
  List<LanguageModel> openMenuRowOrder(WidgetTester tester) {
    return tester
        .widgetList<LanguageDropDownEntry>(find.byType(LanguageDropDownEntry))
        .map((entry) => entry.languageModel)
        .toList();
  }

  testWidgets(
    'sorts analytics languages to the top, alphabetically below the rule',
    (tester) async {
      MatrixState.pangeaController.userController.setPublicProfile(
        PublicProfileModel(
          analytics: AnalyticsProfileModel(
            languageAnalytics: {
              spanish: LanguageAnalyticsProfileEntry(4, 0),
              french: LanguageAnalyticsProfileEntry(7, 0),
            },
          ),
        ),
      );

      await openDropdown(tester);

      final rowOrder = openMenuRowOrder(tester);
      final frenchIndex = rowOrder.indexOf(french);
      final spanishIndex = rowOrder.indexOf(spanish);
      final italianIndex = rowOrder.indexOf(italian);

      expect(frenchIndex, isNonNegative);
      expect(spanishIndex, isNonNegative);
      expect(italianIndex, isNonNegative);
      // Alphabetical within the analytics group (French before Spanish), and
      // both ahead of Italian, which has no analytics.
      expect(frenchIndex, lessThan(spanishIndex));
      expect(spanishIndex, lessThan(italianIndex));

      expect(find.text(enL10n.languageDropdownLevel(7)), findsOneWidget);
      expect(find.text(enL10n.languageDropdownLevel(4)), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    },
  );

  testWidgets(
    'renders the plain alphabetical list for a learner with no analytics',
    (tester) async {
      await openDropdown(tester);

      final rowOrder = openMenuRowOrder(tester);
      expect(rowOrder, containsAllInOrder([french, italian, spanish]));
      expect(find.byType(Divider), findsNothing);
    },
  );

  testWidgets('leaves the base-language list unaffected by analytics', (
    tester,
  ) async {
    MatrixState.pangeaController.userController.setPublicProfile(
      PublicProfileModel(
        analytics: AnalyticsProfileModel(
          languageAnalytics: {french: LanguageAnalyticsProfileEntry(7, 0)},
        ),
      ),
    );

    await openDropdown(tester, isL2List: false);

    expect(find.byType(Divider), findsNothing);
    expect(find.text(enL10n.languageDropdownLevel(7)), findsNothing);
  });

  testWidgets(
    'keeps the circle avatar for an analytics language with no usable flag',
    (tester) async {
      // Plain Spanish has a localized sibling (Spanish (Mexico)), so
      // LanguageModel.shouldShowFlag is false for it — the row must not fall
      // to LanguageFlagChip's own two-letter code badge, which reads as
      // squished next to every other row's full circle or real flag.
      MatrixState.pangeaController.userController.setPublicProfile(
        PublicProfileModel(
          analytics: AnalyticsProfileModel(
            languageAnalytics: {
              spanish: LanguageAnalyticsProfileEntry(15, 0),
              spanishMexico: LanguageAnalyticsProfileEntry(3, 0),
            },
          ),
        ),
      );

      await openDropdown(tester);

      final spanishEntry = find.byWidgetPredicate(
        (w) => w is LanguageDropDownEntry && w.languageModel == spanish,
      );
      final spanishMexicoEntry = find.byWidgetPredicate(
        (w) => w is LanguageDropDownEntry && w.languageModel == spanishMexico,
      );

      expect(
        find.descendant(of: spanishEntry, matching: find.byType(Avatar)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: spanishEntry,
          matching: find.byType(LanguageFlagChip),
        ),
        findsNothing,
      );
      expect(find.text(enL10n.languageDropdownLevel(15)), findsOneWidget);

      // Spanish (Mexico) is unambiguous, so it keeps its flag.
      expect(
        find.descendant(
          of: spanishMexicoEntry,
          matching: find.byType(LanguageFlagChip),
        ),
        findsOneWidget,
      );
      expect(find.text(enL10n.languageDropdownLevel(3)), findsOneWidget);
    },
  );
}
