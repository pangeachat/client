import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

/// Shared layout metrics and text style for the goal header, used by both its
/// faces (the collapsed header and the expanded content) and both wrappers.
class GoalHeaderConstants {
  /// Width reserved on each side of the top row so the centered content stays
  /// centered while the chevron sits flush right.
  static const double chevronSlot = 24.0;

  /// Padding above the star row (collapsed) and above the first goal row
  /// (expanded), kept identical so the top of the header doesn't shift on
  /// expand.
  static const double topPadding = 14.0;

  /// Max height of the scrolling portion of the goal list (the goals below the
  /// pinned top row). Sized to hold ~3 two-line rows, so a 4-goal list — one
  /// pinned plus three here — never scrolls however long each goal is.
  static const double goalsScrollMaxHeight = 190.0;

  /// The emphasized 15px label shared by the goal header's title and its
  /// active-goal subtitle, across both faces and both wrappers.
  static const TextStyle labelStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}

/// A centered [GoalHeaderConstants.labelStyle] label
Text goalHeaderLabel(String text) => Text(
  text,
  textAlign: TextAlign.center,
  style: GoalHeaderConstants.labelStyle,
);

/// The first goal not yet completed, or null when every goal is done.
ActivityRoleGoal? firstIncompleteGoal(
  List<ActivityRoleGoal> goals,
  bool Function(ActivityRoleGoal) isComplete,
) {
  for (final goal in goals) {
    if (!isComplete(goal)) return goal;
  }
  return null;
}

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
        ? goalHeaderLabel(title)
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
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12.0,
              GoalHeaderConstants.topPadding,
              12.0,
              subtitle != null ? 0.0 : GoalHeaderConstants.topPadding,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16.0,
              10.0,
              16.0,
              GoalHeaderConstants.topPadding,
            ),
            child: subtitle,
          ),
      ],
    );
  }
}
