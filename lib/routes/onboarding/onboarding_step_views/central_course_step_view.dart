import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_course_card.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_step_body.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/central_course_onboarding_step.dart';

class CentralCourseStepView extends StatelessWidget {
  final CentralCourseOnboardingStep step;
  final bool loading;
  final Object? error;
  final bool hasNextStep;
  final VoidCallback forward;

  const CentralCourseStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.error,
    required this.hasNextStep,
    required this.forward,
  });

  void _choose({required bool ownCourse}) {
    step.chooseOwnCourse(ownCourse);
    forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final central = step.central;
    final name = step.plan?.title ?? central.room.name ?? '';
    final title = l10n.centralCourseOfferTitle(name);

    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: OnboardingStepBody(
              label: title,
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  OnboardingCourseCard(
                    avatar: central.room.avatarUrl,
                    name: name,
                    plan: step.plan,
                    courseRoomId: null,
                  ),
                  // Joining puts the learner in front of strangers, so the
                  // page says so before they choose.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      l10n.centralCourseMembersSeeYou,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Column(
          spacing: 8.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            OnboardingForwardButton(
              onPressed: () => _choose(ownCourse: false),
              label: l10n.join,
              loading: loading,
              error: error,
            ),
            TextButton(
              onPressed: loading ? null : () => _choose(ownCourse: true),
              child: Text(l10n.makeMyOwnCourseInstead),
            ),
          ],
        ),
      ],
    );
  }
}
