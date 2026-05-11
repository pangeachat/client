import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/course_code_onboarding_step.dart';
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
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    child: Text(
      step is CourseCodeOnboardingStep
          ? L10n.of(context).courseCodeStepSkip
          : L10n.of(context).skipForNow,
    ),
  );
}
