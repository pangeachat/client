import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';

class JoinedCourseOnboardingStep extends OnboardingStep {
  const JoinedCourseOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  /// The trial page follows for a user still inside the trial window, so this
  /// page is not always the last step — [maxRemainingSteps] has to say so, or
  /// its button reads "Let's go" with a page still to come.
  static JoinedCourseOnboardingStep next({
    required Client client,
    required OnboardingStateController state,
  }) => JoinedCourseOnboardingStep(
    client: client,
    state: state,
    maxRemainingSteps: state.trialInfoProvider.shouldShowTrialPage ? 1 : 0,
  );

  @override
  Future<OnboardingStep?> execute() async =>
      state.trialInfoProvider.shouldShowTrialPage
      ? FreeTrialOnboardingStep(
          client: client,
          state: state,
          maxRemainingSteps: 0,
        )
      : null;

  @override
  OnboardingStep? skip() => state.trialInfoProvider.shouldShowTrialPage
      ? FreeTrialOnboardingStep(
          client: client,
          state: state,
          maxRemainingSteps: 0,
        )
      : null;
}
