import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/locale_provider.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/pick_language_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';
import 'announcement_capture.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #8690 — the target-language grid must reach assistive tech: each tile
/// reads as a button with a selected state, the scroll view reports how many
/// languages the search left, and picking or unpicking a language is
/// announced.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});

    // The grid tiles fetch flag SVGs through SvgRepo, which reads a GetStorage
    // cache; GetStorage needs path_provider, so stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('pick_language_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('svg_cache');

    client = await getTestClient();
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
    // The CMS is unreachable in tests, so this settles on the hardcoded
    // fallback list — enough to fill targetOptions before any widget builds.
    await PLanguageStore.initialize();
  });

  tearDownAll(() => client.dispose());

  Future<void> pumpStep(WidgetTester tester) async {
    final state = OnboardingStateController(
      accountUpdater: MockAccountUpdater(),
      courseProvider: MockCourseProvider(),
      avatarProvider: MockAvatarProvider(),
      trialInfoProvider: MockTrialInfoProvider(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
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
    // Two zero-duration pumps: the first builds before the async localization
    // delegate resolves, the second rebuilds with L10n available. No
    // pumpAndSettle — the flag placeholders animate indefinitely.
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    // Flush the deferred app-language switch the base-language seed schedules.
    await tester.pump(const Duration(milliseconds: 600));
  }

  Finder tile(String name) => find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.text(name),
  );

  testWidgets('a picked language reads as a selected button and is announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final announcements = captureAnnouncements(tester);
    await pumpStep(tester);
    // Entering the step seeds the base language — state the user didn't just
    // change — so it must stay silent; only the user's own taps announce.
    expect(announcements, isEmpty);

    await tester.enterText(find.byType(TextField), 'Spanish');
    await tester.pump();

    await tester.tap(tile('Spanish'));
    await tester.pump();

    expect(
      tester.getSemantics(tile('Spanish')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(announcements, ['Selected Spanish as target language']);

    // Tapping the selected language again clears the choice.
    await tester.tap(tile('Spanish'));
    await tester.pump();

    expect(
      tester.getSemantics(tile('Spanish')),
      isSemantics(isButton: true, isSelected: false, hasSelectedState: true),
    );
    expect(announcements, [
      'Selected Spanish as target language',
      'Reset target language',
    ]);

    semantics.dispose();
  });

  testWidgets('the grid reports the filtered language count to semantics', (
    tester,
  ) async {
    await pumpStep(tester);

    await tester.enterText(find.byType(TextField), 'Spanish');
    await tester.pump();

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    // The filter is narrow enough that every match renders, so the declared
    // count must equal the tiles actually built.
    final tileCount = tester
        .widgetList(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(InkWell),
          ),
        )
        .length;
    expect(tileCount, greaterThan(0));
    expect(scrollView.semanticChildCount, tileCount);
  });
}
