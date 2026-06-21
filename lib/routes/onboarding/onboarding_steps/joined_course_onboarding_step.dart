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
    if (roomId == null) return "/rooms";
    return "/rooms/spaces/$roomId";
  }

  @override
  Future<OnboardingStep?> execute() async => null;

  @override
  OnboardingStep? skip() => null;
}
