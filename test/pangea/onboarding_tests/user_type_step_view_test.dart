import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/user_type_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
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

/// #8639 — the selected option must not share the forward CTA's styling, and
/// once a choice is made the unselected option dims to half opacity so the
/// selection reads at a glance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    client = await getTestClient();
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
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
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: UserTypeStepView(
            step: UserTypeOnboardingStep(
              client: client,
              state: state,
              maxRemainingSteps: 3,
            ),
            loading: false,
            hasNextStep: true,
            forward: () {},
          ),
        ),
      ),
    );
    // Two zero-duration pumps: the first builds before the async localization
    // delegate resolves, the second rebuilds with L10n available.
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  double optionOpacity(WidgetTester tester, String label) => tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.widgetWithText(ElevatedButton, label),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  Color? buttonBackground(WidgetTester tester, Finder button) =>
      tester.widget<ElevatedButton>(button).style?.backgroundColor?.resolve({});

  testWidgets('selecting an option dims the other one', (tester) async {
    await pumpStep(tester);

    expect(optionOpacity(tester, 'Teach'), 1.0);
    expect(optionOpacity(tester, 'Learn'), 1.0);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Learn'));
    await tester.pump();

    expect(optionOpacity(tester, 'Learn'), 1.0);
    expect(optionOpacity(tester, 'Teach'), 0.5);
  });

  testWidgets('the selected option is styled unlike the forward CTA', (
    tester,
  ) async {
    await pumpStep(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Learn'));
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(UserTypeStepView)));
    final selectedColor = buttonBackground(
      tester,
      find.widgetWithText(ElevatedButton, 'Learn'),
    );
    final ctaColor = buttonBackground(
      tester,
      find.descendant(
        of: find.byType(OnboardingForwardButton),
        matching: find.byType(ElevatedButton),
      ),
    );

    expect(selectedColor, theme.colorScheme.primaryContainer);
    expect(ctaColor, theme.colorScheme.primary);
    expect(ctaColor, isNot(selectedColor));
  });

  // #8690 — the choice must reach assistive tech, not just sighted users: the
  // chosen option carries the semantics selected flag, and each selection is
  // announced to the screen reader.
  testWidgets('the chosen option reads as selected and is announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final announcements = captureAnnouncements(tester);
    await pumpStep(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Learn'));
    await tester.pump();

    expect(
      tester.getSemantics(find.widgetWithText(ElevatedButton, 'Learn')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.widgetWithText(ElevatedButton, 'Teach')),
      isSemantics(isSelected: false, hasSelectedState: true),
    );
    expect(announcements, ['Learn selected']);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Teach'));
    await tester.pump();

    expect(
      tester.getSemantics(find.widgetWithText(ElevatedButton, 'Teach')),
      isSemantics(isSelected: true),
    );
    expect(announcements, ['Learn selected', 'Teach selected']);

    semantics.dispose();
  });
}
