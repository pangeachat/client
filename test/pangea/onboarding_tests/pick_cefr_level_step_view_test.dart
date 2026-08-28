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
import 'package:fluffychat/routes/onboarding/onboarding_step_views/pick_cefr_level_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// #8391 — the CEFR step reassures the learner that the level they pick is
/// not permanent, so the choice feels lower-stakes during onboarding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const subtitle = 'You can change this later';

  late Client client;

  setUpAll(() async {
    // The view seeds its highlight from the user controller's profile, so it
    // needs a controller reachable through MatrixState. The controller builds
    // a PLanguageStore, which reads its cache from shared preferences.
    SharedPreferences.setMockInitialValues({});
    client = await getTestClient();
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
  });

  tearDownAll(() => client.dispose());

  Future<void> pumpStep(WidgetTester tester, UserType type) async {
    final state = OnboardingStateController(
      accountUpdater: MockAccountUpdater(),
      courseProvider: MockCourseProvider(),
      avatarProvider: MockAvatarProvider(),
      trialInfoProvider: MockTrialInfoProvider(),
    )..setUserType(type);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: PickCefrLevelStepView(
            step: PickCefrLevelOnboardingStep(
              client: client,
              state: state,
              maxRemainingSteps: 1,
            ),
            loading: false,
            hasNextStep: false,
            forward: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('student sees the reassurance under the title', (tester) async {
    await pumpStep(tester, UserType.student);

    expect(find.text('What level are you?'), findsOneWidget);
    expect(find.text(subtitle), findsOneWidget);
  });

  testWidgets('teacher sees it too — both write the same profile setting', (
    tester,
  ) async {
    await pumpStep(tester, UserType.teacher);

    expect(find.text('What level do you teach?'), findsOneWidget);
    expect(find.text(subtitle), findsOneWidget);
  });

  testWidgets('the reassurance is announced with the title, not alone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpStep(tester, UserType.student);

    expect(
      find.bySemanticsLabel('What level are you?\n$subtitle'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  // #8639 — once a level is picked, the unselected levels dim to half opacity
  // so the selection reads at a glance.
  testWidgets('selecting a level dims the other levels', (tester) async {
    await pumpStep(tester, UserType.student);

    double levelOpacity(String title) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.widgetWithText(ElevatedButton, title),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    // The profile default (A1) is seeded as selected on entry.
    expect(levelOpacity('Novice Mid (A1)'), 1.0);
    expect(levelOpacity('Novice High (A2)'), 0.5);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Novice High (A2)'));
    await tester.pump();

    expect(levelOpacity('Novice High (A2)'), 1.0);
    expect(levelOpacity('Novice Mid (A1)'), 0.5);
    expect(levelOpacity('Novice Low (Pre A1)'), 0.5);
  });
}
