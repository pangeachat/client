import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class JoinedCourseOnboardingStep extends OnboardingStep {
  final CoursePlanModel coursePlan;
  final String roomId;

  const JoinedCourseOnboardingStep({
    required super.client,
    super.stepIndex = 4,
    super.totalSteps = 4,
    required super.prevStep,
    required this.coursePlan,
    required this.roomId,
  });

  @override
  OnboardingStep? get nextStep => null;

  @override
  String get stepDestination => "/rooms/spaces/$roomId";

  @override
  Future<void> execute() async {}
}
