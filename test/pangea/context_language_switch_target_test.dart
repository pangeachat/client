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

import 'package:fluffychat/features/languages/context_language_switch_target.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/svg_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_switcher_sheet.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #8495 — the tap/tint decision every context language chip shares
/// (profile.instructions.md, "Switching from context", point 6): the
/// activity start page's info row, a course's info chips, and a running
/// session's goal header all route through this one widget.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late L10n enL10n;
  late LanguageModel french;
  late LanguageModel spanish;
  late LanguageModel english;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'context_language_switch_target',
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
          {'language_code': 'en', 'language_name': 'English'},
        ],
      }),
    });
    await PLanguageStore.initialize();

    client = await prepareTestClient();
    french = PLanguageStore.byLangCode('fr')!;
    spanish = PLanguageStore.byLangCode('es')!;
    english = PLanguageStore.byLangCode('en')!;
    enL10n = await lookupL10n(const Locale('en'));

    // The switcher sheet the "switchable" case opens renders every target
    // language's flag inline, each an NetworkSvg fetch — warm SvgRepo's
    // cache first so pumpAndSettle never waits on the real fetch (the
    // loading placeholder is an indeterminate spinner it can't wait out;
    // see p_language_dropdown_test.dart).
    const flagSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>';
    await http.runWithClient(
      () => Future.wait([
        SvgRepo.get(french.svgUrl.toString()),
        SvgRepo.get(spanish.svgUrl.toString()),
      ]),
      () => MockClient((_) async => http.Response(flagSvg, 200)),
    );
  });

  tearDownAll(() => client.dispose());

  /// Seeds L1/L2 directly on the client's account-data cache — bypassing the
  /// network write, since build() only ever reads this synchronously — then
  /// constructs a fresh controller (mirrors p_language_dropdown_test.dart's
  /// pattern).
  void seedController({required String base, required String target}) {
    client.accountData[UserConstants.userProfile] = BasicEvent(
      type: UserConstants.userProfile,
      content: Profile(
        userSettings: UserSettings(
          sourceLanguage: base,
          targetLanguage: target,
        ),
      ).toJson(),
    );
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
  }

  Future<void> pumpChip(
    WidgetTester tester,
    LanguageModel? contentLanguage,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ContextLanguageSwitchTarget(
            contentLanguage: contentLanguage,
            builder: (context, canSwitch) => Text(
              canSwitch ? 'switchable' : 'not switchable',
              key: const Key('chip'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a mismatched language is tappable and opens the switcher', (
    tester,
  ) async {
    seedController(base: 'en', target: 'fr');
    await pumpChip(tester, spanish);

    expect(find.text('switchable'), findsOneWidget);
    expect(
      find.bySemanticsLabel(enL10n.switchLanguageChipLabel('Spanish')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('chip')));
    await tester.pumpAndSettle();

    expect(find.byType(LanguageSwitcherSheet), findsOneWidget);
  });

  testWidgets('the current target language is plain and not tappable', (
    tester,
  ) async {
    seedController(base: 'en', target: 'fr');
    await pumpChip(tester, french);

    expect(find.text('not switchable'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    expect(find.bySemanticsLabel('French'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chip')));
    await tester.pumpAndSettle();

    expect(find.byType(LanguageSwitcherSheet), findsNothing);
  });

  testWidgets('the base language is plain and not tappable', (tester) async {
    seedController(base: 'en', target: 'fr');
    await pumpChip(tester, english);

    expect(find.text('not switchable'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });
}
