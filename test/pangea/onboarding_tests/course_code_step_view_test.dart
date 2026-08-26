import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/course_code_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import '../get_test_client.dart';

/// #8598 — on a phone the software keyboard shrinks the step to well under the
/// height its content needs. The centred content used to overflow its box and
/// paint over the buttons below it; it has to scroll instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // BotFace falls back to a CachedNetworkImage, whose cache manager needs
    // path_provider; stub the channel to a temp dir.
    final tempDir = Directory.systemTemp.createTempSync('course_code_step');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    client = await getTestClient();
  });

  tearDownAll(() => client.dispose());

  testWidgets('code input never overlaps the buttons below it', (tester) async {
    tester.view.physicalSize = const Size(390.0, 780.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final step = CourseCodeOnboardingStep(
      client: client,
      state: OnboardingStateController(
        accountUpdater: MockAccountUpdater(),
        courseProvider: MockCourseProvider(),
        avatarProvider: MockAvatarProvider(),
        trialInfoProvider: MockTrialInfoProvider(),
      ),
      maxRemainingSteps: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          // Mirrors the onboarding page's body wrapper.
          body: Center(
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(maxWidth: step.contentMaxWidth),
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 48.0,
              ),
              child: CourseCodeStepView(
                step: step,
                loading: false,
                error: null,
                hasNextStep: true,
                forward: () {},
                skip: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // The async L10n delegate leaves the home empty on the very first frame.
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    final l10n = L10n.of(tester.element(find.byType(CourseCodeStepView)));

    // "Yes" swaps the two choices for the code input.
    await tester.tap(find.widgetWithText(ElevatedButton, l10n.yes));
    await tester.pump();

    // With room to spare the content stays centred rather than pinned to the
    // top of the step.
    expect(
      tester.getRect(find.byType(BotFace)).top,
      greaterThan(tester.getRect(find.byType(CourseCodeStepView)).top),
    );

    // Focusing the input raises the keyboard, which leaves the step roughly
    // this much room — less than the bot face, title and input need.
    await tester.tap(find.byType(TextField));
    tester.view.physicalSize = const Size(390.0, 330.0);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final input = tester.getRect(find.byType(TextField));
    final skip = tester.getRect(
      find.widgetWithText(TextButton, l10n.courseCodeStepSkip),
    );

    expect(input.bottom, lessThanOrEqualTo(skip.top));
  });
}
