import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';

class JoinedCourseOnboardingStep extends OnboardingStep {
  const JoinedCourseOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  // world_v2: a joined course opens as a token-native `course` panel
  // (`WorkspaceNav.openCourseSection`), not a path — building that needs the
  // current workspace URI, which only `OnboardingController` (with a
  // `BuildContext`) has. This step exposes the space id via
  // [joinedCourseSpaceId]; the base [stepDestination] (the chat list) is the
  // fallback the controller uses only when no space id is set. See
  // `routing.instructions.md`.
  @override
  String? get joinedCourseSpaceId => state.joinedRoomId;

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
