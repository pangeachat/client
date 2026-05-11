import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class JoinedCourseOnboardingStep extends OnboardingStep {
  final CoursePlanModel coursePlan;
  final String roomId;

  const JoinedCourseOnboardingStep({
    required super.client,
    required super.maxTotalSteps,
    required this.coursePlan,
    required this.roomId,
  });

  @override
  String get stepDestination => "/rooms/spaces/$roomId";

  @override
  Future<OnboardingStep?> execute() async => null;

  @override
  OnboardingStep? skip() => null;
}
