import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_join_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

class UserTypeOnboardingStep extends OnboardingStep with CourseJoinStep {
  UserTypeOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  void setUserType(UserType type) => state.setUserType(type);

  @override
  bool get enableGoForward => state.userType != null;

  Future<OnboardingStep?> _getNextStep() async {
    final type = state.userType;
    if (type == null) {
      throw StateError("Must set user type to move to next step");
    }

    final courseCode = state.courseProvider.getCachedJoinCode();
    if (courseCode != null) {
      try {
        final roomId = await state.courseProvider.joinSpaceWithCode(courseCode);
        // Only a failed JOIN falls through to the code step. A joined course
        // whose quest doesn't resolve continues as a joined-course flow
        // (#8593) — see joining-courses.instructions.md.
        return await stepAfterJoin(roomId);
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'cached_course_id': courseCode},
        );
      } finally {
        // Onboarding is finished with the cached inbound code either way:
        // joined on success, handed off to manual entry on failure. A
        // leftover would surprise-join a later login (#7524).
        await state.courseProvider.clearCachedJoinCode();
      }
    }

    final maxRemainingSteps = switch (state.userType) {
      UserType.student => 2,
      UserType.teacher => 3,
      null => 2,
    };

    return CourseCodeOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: maxRemainingSteps,
    );
  }

  @override
  Future<OnboardingStep?> execute() async => _getNextStep();

  @override
  OnboardingStep? skip() {
    throw StateError("Cannot skip user type onboarding step");
  }
}
