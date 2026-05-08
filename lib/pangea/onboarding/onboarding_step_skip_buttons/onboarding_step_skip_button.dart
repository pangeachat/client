import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/onboarding/onboarding_step_skip_buttons/course_code_step_skip_button.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_skip_buttons/custom_course_step_skip_button.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class OnboardingStepSkipButton extends StatelessWidget {
  final OnboardingStep step;
  final VoidCallback onPressed;
  const OnboardingStepSkipButton({
    super.key,
    required this.step,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final step = this.step;
    if (!step.canSkip) {
      return SizedBox();
    }

    if (step is CourseCodeOnboardingStep) {
      return CourseCodeStepSkipButton(step: step, onPressed: onPressed);
    }

    if (step is CustomCourseOnboardingStep) {
      return CustomCourseStepSkipButton(step: step, onPressed: onPressed);
    }

    return SizedBox();
  }
}
