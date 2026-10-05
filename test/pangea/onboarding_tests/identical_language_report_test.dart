import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_mismatch_popup.dart';
import '../get_test_client.dart';

/// #8835: the same language in both pickers is rejected input the step view
/// already displays. Sentry is uninitialized here, so captures no-op; these
/// tests pin that the step still refuses to advance and that the report goes
/// through [ErrorHandler.logErrorOnce] under one key — a second tap must not
/// spend a second event.
void main() {
  late final Client client;

  setUpAll(() async {
    client = await getTestClient();
  });

  setUp(ErrorHandler.resetReportedOnceKeysForTest);
  tearDown(ErrorHandler.resetReportedOnceKeysForTest);

  OnboardingNavigationController controllerWithIdenticalLanguages() {
    final state = OnboardingStateController(
      accountUpdater: MockAccountUpdater(),
      courseProvider: MockCourseProvider(),
      avatarProvider: MockAvatarProvider(),
      trialInfoProvider: MockTrialInfoProvider(),
    );
    final spanish = LanguageModel(langCode: 'es', displayName: 'Spanish');
    state.setBaseLanguage(spanish);
    state.setTargetLanguage(spanish);
    return OnboardingNavigationController(
      initialStep: PickLanguageOnboardingStep(
        client: client,
        state: state,
        maxRemainingSteps: 1,
      ),
    );
  }

  test('forward() stays on the step with IdenticalLanguageException', () async {
    final controller = controllerWithIdenticalLanguages();
    final result = await controller.forward();
    expect(result, isA<ErrorNavigationResult>());
    expect(
      (result as ErrorNavigationResult).error,
      isA<IdenticalLanguageException>(),
    );
    expect(controller.step, isA<PickLanguageOnboardingStep>());
  });

  test('reports once per session, so a repeat tap spends no event', () async {
    final controller = controllerWithIdenticalLanguages();
    await controller.forward();
    // forward() spent the key: a fresh report on it is suppressed.
    expect(
      await ErrorHandler.logErrorOnce(
        key: IdenticalLanguageException.reportKey,
        e: IdenticalLanguageException(),
        data: {},
      ),
      isFalse,
    );
    expect(await controller.forward(), isA<ErrorNavigationResult>());
  });
}
