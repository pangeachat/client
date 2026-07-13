import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

class ActivityDropdownHeader extends StatelessWidget {
  final ActivityRoleGoal goal;
  final bool isGoalCompleted;
  final VoidCallback toggleShowDropdown;
  final Widget? trailing;
  final bool animateGoalTransitions;

  const ActivityDropdownHeader({
    super.key,
    required this.goal,
    required this.isGoalCompleted,
    required this.toggleShowDropdown,
    this.trailing,
    this.animateGoalTransitions = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goalIndicator = Row(
      key: ValueKey(goal.id),
      children: [
        Expanded(
          child: GoalStatusWidget(
            goal: goal,
            complete: isGoalCompleted,
            starTarget: ActivitySessionConstants.goalMenuStarTargetId(goal.id),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ?trailing,
      ],
    );

    return InkWell(
      onTap: toggleShowDropdown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
          color: theme.colorScheme.surface,
        ),
        child: animateGoalTransitions
            ? AnimatedSwitcher(
                duration: FluffyThemes.animationDuration,
                transitionBuilder: (child, animation) {
                  final isCurrent = child.key == ValueKey(goal.id);

                  return ClipRect(
                    child: AnimatedBuilder(
                      animation: animation,
                      child: child,
                      builder: (context, child) {
                        final offset = isCurrent
                            // New item: 1 -> 0
                            ? Offset(0, 1 - animation.value)
                            // Old item: 0 -> -1
                            : Offset(0, animation.value - 1);

                        return FractionalTranslation(
                          translation: offset,
                          child: child,
                        );
                      },
                    ),
                  );
                },
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previousChildren, ?currentChild],
                  );
                },
                child: goalIndicator,
              )
            : goalIndicator,
      ),
    );
  }
}
