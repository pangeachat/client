import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';

class JoinedCourseOnboardingStep extends OnboardingStep {
  const JoinedCourseOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  @override
  String get stepDestination {
    final roomId = state.joinedRoomId;
    if (roomId == null) return PRoutes.chatsList;
    // world_v2: a joined course is `/courses/<bareLocalpart>` (PRoutes.course),
    // not the retired `/rooms/spaces/:spaceid` shape. Passing the FULL room id
    // through the legacy redirect mis-parses it (the same break as the course
    // chooser fix) and dead-ends onboarding. PRoutes.course bares the id so the
    // redirect resolves to the course workspace.
    return PRoutes.course(roomId);
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
