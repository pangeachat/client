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
  final bool loading;
  final Object? error;
  final bool hasNextStep;
  final VoidCallback forward;
  final VoidCallback skip;
  final VoidCallback updateNavigationButton;

  const OnboardingStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.error,
    required this.hasNextStep,
    required this.forward,
    required this.skip,
    required this.updateNavigationButton,
  });

  @override
  Widget build(BuildContext context) {
    final step = this.step;

    if (step is ProfileSetupOnboardingStep) {
      return ProfileSetupStepView(
        step: step,
        loading: loading,
        hasNextStep: hasNextStep,
        forward: forward,
      );
    }

    if (step is UserTypeOnboardingStep) {
      return UserTypeStepView(
        step: step,
        loading: loading,
        hasNextStep: hasNextStep,
        forward: forward,
      );
    }

    if (step is CourseCodeOnboardingStep) {
      return CourseCodeStepView(
        step: step,
        loading: loading,
        error: error,
        hasNextStep: hasNextStep,
        forward: forward,
        skip: skip,
      );
    }

    if (step is JoinedCourseOnboardingStep) {
      return JoinedCourseStepView(
        step: step,
        loading: loading,
        hasNextStep: hasNextStep,
        forward: forward,
      );
    }

    if (step is PickLanguageOnboardingStep) {
      return PickLanguageStepView(
        step: step,
        loading: loading,
        error: error,
        hasNextStep: hasNextStep,
        forward: forward,
      );
    }

    if (step is PickCefrLevelOnboardingStep) {
      return PickCefrLevelStepView(
        step: step,
        loading: loading,
        hasNextStep: hasNextStep,
        forward: forward,
      );
    }

    if (step is CustomCourseOnboardingStep) {
      return CustomCourseStepView(
        step: step,
        loading: loading,
        hasNextStep: hasNextStep,
        forward: forward,
        skip: skip,
      );
    }

    return SizedBox();
  }
}
