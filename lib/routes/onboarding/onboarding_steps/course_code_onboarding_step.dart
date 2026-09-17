import 'dart:async';

import 'package:fluffychat/routes/onboarding/onboarding_steps/course_join_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

class CourseCodeOnboardingStep extends OnboardingStep with CourseJoinStep {
  CourseCodeOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  @override
  bool get enableGoForward =>
      state.courseCode != null && state.courseCode!.isNotEmpty;

  void setCourseCode(String code) => state.setCourseCode(code);

  @override
  Future<OnboardingStep?> execute() async {
    final code = state.courseCode;
    if (code == null) {
      throw StateError("Course code in null");
    }

    // A failed join throws, and the step surfaces the error. A join that
    // succeeds always advances, even when the course's quest doesn't resolve
    // (#8593) — see joining-courses.instructions.md.
    final roomId = await state.courseProvider.joinSpaceWithCode(code);
    return stepAfterJoin(roomId);
  }

  @override
  OnboardingStep? skip() {
    final maxRemainingSteps = switch (state.userType) {
      UserType.student => 1,
      UserType.teacher => 2,
      null => 1,
    };

    return PickLanguageOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: maxRemainingSteps,
    );
  }
}
