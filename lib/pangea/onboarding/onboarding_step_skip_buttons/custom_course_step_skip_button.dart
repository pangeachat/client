import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';

class CustomCourseStepSkipButton extends StatelessWidget {
  final CustomCourseOnboardingStep step;
  final VoidCallback onPressed;

  const CustomCourseStepSkipButton({
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
    return TextButton(
      onPressed: _onPressed,
      child: Text(L10n.of(context).skipForNow),
    );
  }
}
