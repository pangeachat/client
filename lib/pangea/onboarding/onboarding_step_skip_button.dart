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

  void _onPressed() {
    step.skip();
    onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final step = this.step;
    if (!step.enableSkip) {
      return SizedBox();
    }

    String text = L10n.of(context).skipForNow;
    if (step is CourseCodeOnboardingStep) {
      text = L10n.of(context).courseCodeStepSkip;
    }

    return TextButton(onPressed: _onPressed, child: Text(text));
  }
}
