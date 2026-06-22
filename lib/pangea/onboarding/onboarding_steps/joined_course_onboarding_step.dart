import 'package:fluffychat/pangea/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class JoinedCourseOnboardingStep extends OnboardingStep {
  const JoinedCourseOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  @override
  String get stepDestination {
    final roomId = state.joinedRoomId;
    if (roomId == null) return "/rooms";
    return "/rooms/spaces/$roomId";
  }

  @override
  Future<OnboardingStep?> execute() async =>
      state.trialInfoProvider.shouldShowTrialPage
      ? FreeTrialOnboardingStep(
          client: client,
          state: state,
          maxRemainingSteps: maxRemainingSteps,
        )
      : null;

  @override
  OnboardingStep? skip() => state.trialInfoProvider.shouldShowTrialPage
      ? FreeTrialOnboardingStep(
          client: client,
          state: state,
          maxRemainingSteps: maxRemainingSteps,
        )
      : null;
}
