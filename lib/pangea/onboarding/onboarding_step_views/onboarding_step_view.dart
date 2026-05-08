import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/onboarding/onboarding_step_views/course_code_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_views/custom_course_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_views/joined_course_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_views/pick_cefr_level_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_views/pick_language_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_views/profile_setup_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_views/user_type_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/user_type_onboarding_step.dart';

class OnboardingStepView extends StatelessWidget {
  final OnboardingStep step;
  final VoidCallback onUpdate;
  final Object? error;

  const OnboardingStepView({
    super.key,
    required this.step,
    required this.onUpdate,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final step = this.step;

    if (step is ProfileSetupOnboardingStep) {
      return ProfileSetupStepView(step: step);
    }

    if (step is UserTypeOnboardingStep) {
      return UserTypeStepView(step: step, onUpdate: onUpdate);
    }

    if (step is CourseCodeOnboardingStep) {
      return CourseCodeStepView(step: step, onUpdate: onUpdate, error: error);
    }

    if (step is JoinedCourseOnboardingStep) {
      return JoinedCourseStepView(step: step);
    }

    if (step is PickLanguageOnboardingStep) {
      return PickLanguageStepView(step: step, onUpdate: onUpdate, error: error);
    }

    if (step is PickCefrLevelOnboardingStep) {
      return PickCefrLevelStepView(step: step, onUpdate: onUpdate);
    }

    if (step is CustomCourseOnboardingStep) {
      return CustomCourseStepView(step: step);
    }

    return SizedBox();
  }
}
