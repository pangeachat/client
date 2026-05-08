import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';

class CustomCourseStepView extends StatelessWidget {
  final CustomCourseOnboardingStep step;
  const CustomCourseStepView({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 8.0,
      children: [
        Text(
          L10n.of(context).customCourseStepTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        TextField(decoration: InputDecoration(hintText: L10n.of(context).name)),
        TextField(
          decoration: InputDecoration(hintText: L10n.of(context).email),
        ),
        TextField(
          decoration: InputDecoration(
            hintText: L10n.of(context).aboutYourClass,
          ),
          minLines: 10,
          maxLines: 10,
        ),
      ],
    );
  }
}
