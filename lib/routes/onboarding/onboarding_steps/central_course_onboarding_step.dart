import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';

/// After the level step, a learner with no class code chooses: join their
/// language's central course, or have a private course of their own made on
/// its plan. Either way onboarding ends on that course. See
/// joining-courses.instructions.md § The central course.
class CentralCourseOnboardingStep extends OnboardingStep {
  final PublicCoursesChunk central;

  /// The central course's quest, for the card and for the learner's own
  /// course. Null when it didn't load: their own course then waits for a plan.
  final CoursePlanModel? plan;

  final String language;

  bool _ownCourse = false;

  CentralCourseOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
    required this.central,
    required this.plan,
    required this.language,
  });

  bool get ownCourse => _ownCourse;

  void chooseOwnCourse(bool value) => _ownCourse = value;

  @override
  Future<OnboardingStep?> execute() async {
    // Set once, so stepping back from the trial page can't make a second one.
    if (state.joinedRoomId == null) {
      final plan = this.plan;
      state.setJoinedRoomId(
        _ownCourse
            ? await state.courseProvider.createOwnCourse(
                language: language,
                plan: plan,
              )
            : await state.courseProvider.joinCourse(central.room.roomId),
      );
      if (plan != null) state.setJoinedCoursePlan(plan);
    }
    return state.trialInfoProvider.shouldShowTrialPage
        ? FreeTrialOnboardingStep(
            client: client,
            state: state,
            maxRemainingSteps: 0,
          )
        : null;
  }

  @override
  OnboardingStep? skip() => null;
}
