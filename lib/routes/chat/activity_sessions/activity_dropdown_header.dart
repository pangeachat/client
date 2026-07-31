import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_header_constants.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_header_label.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

/// The collapsed face of the goal header. Its top row — the star summary (or a
/// no-goals [title]) with a down chevron on the right — is the only part that
/// toggles the menu open.
///
/// The star row lives here — not in the expanded list — so it is the persistent
/// fly-up target ([GoalStarAnimation]).
class ActivityDropdownHeader extends StatelessWidget {
  final List<ActivityRoleGoal> goals;
  final bool Function(ActivityRoleGoal) isGoalCompleted;
  final String? activeGoalId;
  final VoidCallback onToggle;

  /// Shown under the top row: the active goal's label, a gold "I'm done!"
  /// button, or nothing (all goals complete, read-only).
  final Widget? subtitle;

  /// No-goals fallback: replaces the star summary with a centered title.
  final String? title;

  const ActivityDropdownHeader({
    super.key,
    required this.goals,
    required this.isGoalCompleted,
    required this.onToggle,
    this.activeGoalId,
    this.subtitle,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final Widget center = title != null
        ? GoalHeaderLabel(title)
        : LayoutBuilder(
            builder: (context, constraints) {
              // Shrink the gap between stars (down to nearly touching) to keep
              // them on one row; Wrap only stacks them when even that overflows.
              const starBox =
                  36.0; // GoalStatusWidget: 28 icon + 4 padding/side
              const maxSpacing = 12.0;
              const minSpacing = 2.0;
              var spacing = maxSpacing;
              if (goals.length > 1) {
                final fit =
                    (constraints.maxWidth - 1 - goals.length * starBox) /
                    (goals.length - 1);
                spacing = fit.clamp(minSpacing, maxSpacing);
              }
              return Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: spacing,
                runSpacing: 4.0,
                children: goals
                    .map(
                      (g) => GoalStatusWidget(
                        goal: g,
                        complete: isGoalCompleted(g),
                        isActive: g.id == activeGoalId,
                        showLabel: false,
                        starTarget:
                            ActivitySessionConstants.goalMenuStarTargetId(g.id),
                      ),
                    )
                    .toList(),
              );
            },
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Only this top row toggles the menu; InkWell gives it a hover/ripple.
        // Its padding is equal above and below so the highlight reads as a
        // symmetric band rather than stopping flush under the stars.
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: GoalHeaderConstants.topPadding,
            ),
            child: Row(
              children: [
                const SizedBox(width: GoalHeaderConstants.chevronSlot),
                Expanded(child: Center(child: center)),
                const SizedBox(
                  width: GoalHeaderConstants.chevronSlot,
                  child: Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
        ),
        if (subtitle != null)
          // No top padding: the toggle row's own bottom padding already
          // separates the subtitle from the stars.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16.0,
              0.0,
              16.0,
              GoalHeaderConstants.topPadding,
            ),
            child: subtitle,
          ),
      ],
    );
  }
}
