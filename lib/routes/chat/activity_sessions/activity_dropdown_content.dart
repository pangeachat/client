import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

class ActivityDropdownContent extends StatelessWidget {
  final List<ActivityRoleGoal> goals;
  final bool Function(ActivityRoleGoal) isGoalCompleted;
  final String? activeGoalId;
  final VoidCallback onToggle;

  /// No-goals fallback: the top toggle row shows this title instead of a goal.
  final String? title;

  final bool showEndForAll;
  final bool showEndForMe;
  final bool showWaitNotDone;

  final bool hasCompletedOwnGoals;
  final bool haveAllRolesCompletedAllGoals;

  final VoidCallback? finishActivityForAll;
  final VoidCallback? finishActivityForMe;
  final VoidCallback? continueActivity;

  const ActivityDropdownContent({
    super.key,
    required this.goals,
    required this.isGoalCompleted,
    required this.onToggle,
    this.activeGoalId,
    this.title,
    this.showEndForAll = false,
    this.showEndForMe = false,
    this.showWaitNotDone = false,
    this.hasCompletedOwnGoals = false,
    this.haveAllRolesCompletedAllGoals = false,
    this.finishActivityForAll,
    this.finishActivityForMe,
    this.continueActivity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final goldColor = AppConfig.goldByTheme(context);

    // The top row is the only toggle target. Padding is applied by the InkWell
    // wrapper below so its hover highlight matches the collapsed header.
    final Widget topRow = goals.isEmpty
        ? Row(
            children: [
              const SizedBox(width: GoalHeaderConstants.chevronSlot),
              Expanded(child: Center(child: GoalHeaderLabel(title ?? ''))),
              const SizedBox(
                width: GoalHeaderConstants.chevronSlot,
                child: Icon(Icons.expand_less),
              ),
            ],
          )
        : _GoalRow(
            goal: goals.first,
            complete: isGoalCompleted(goals.first),
            isActive: goals.first.id == activeGoalId,
            isTop: true,
          );

    final restGoals = goals.length > 1
        ? goals.skip(1).toList()
        : const <ActivityRoleGoal>[];

    final buttons = <Widget>[
      if (showWaitNotDone)
        ElevatedButton(
          onPressed: continueActivity,
          style: ElevatedButton.styleFrom(
            side: BorderSide(
              color: theme.brightness == Brightness.light
                  ? theme.colorScheme.primary.withAlpha(120)
                  : theme.colorScheme.primaryContainer,
              width: 2,
            ),
            foregroundColor: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surface,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                L10n.of(context).waitNotDone,
                style: TextStyle(fontSize: isColumnMode ? 16.0 : 12.0),
              ),
            ],
          ),
        ),
      if (showEndForMe)
        ElevatedButton(
          onPressed: finishActivityForMe,
          style: ElevatedButton.styleFrom(
            backgroundColor: hasCompletedOwnGoals
                ? goldColor
                : theme.colorScheme.primaryContainer,
            foregroundColor: theme.brightness == Brightness.light
                ? null
                : hasCompletedOwnGoals
                ? theme.colorScheme.surface
                : theme.colorScheme.onPrimaryContainer,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                L10n.of(context).completeActivityButton,
                style: TextStyle(fontSize: isColumnMode ? 16.0 : 12.0),
              ),
            ],
          ),
        ),
      if (showEndForAll)
        ElevatedButton(
          onPressed: finishActivityForAll,
          style: ElevatedButton.styleFrom(
            side: BorderSide(
              color: haveAllRolesCompletedAllGoals
                  ? goldColor
                  : theme.brightness == Brightness.light
                  ? theme.colorScheme.primary.withAlpha(120)
                  : theme.colorScheme.primaryContainer,
              width: 2,
            ),
            foregroundColor: haveAllRolesCompletedAllGoals
                ? goldColor
                : theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surface,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                L10n.of(context).endForAll,
                style: TextStyle(fontSize: isColumnMode ? 16.0 : 12.0),
              ),
            ],
          ),
        ),
    ];

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pinned close handle / toggle. The InkWell wraps the top padding and
          // spans the full width so its hover highlight matches the collapsed
          // header (rather than being inset and starting below the padding).
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                12.0,
                GoalHeaderConstants.topPadding,
                12.0,
                0.0,
              ),
              child: topRow,
            ),
          ),
          // The remaining goals scroll within a fixed cap so a long list can't
          // grow to cover the roles. Scrolling here never dismisses the menu.
          if (restGoals.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: GoalHeaderConstants.goalsScrollMaxHeight,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final g in restGoals) ...[
                      const SizedBox(height: 10.0),
                      _GoalRow(
                        goal: g,
                        complete: isGoalCompleted(g),
                        isActive: g.id == activeGoalId,
                        isTop: false,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          // Pinned action buttons — always visible below the scroll.
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final button in buttons) ...[
                  const SizedBox(height: 16.0),
                  button,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single goal line: its star, its description, and — on the pinned top row
/// only — room for the collapse chevron.
class _GoalRow extends StatelessWidget {
  final ActivityRoleGoal goal;
  final bool complete;
  final bool isActive;

  /// Only the top row leaves room for the chevron; the rest run to the edge.
  final bool isTop;

  const _GoalRow({
    required this.goal,
    required this.complete,
    required this.isActive,
    required this.isTop,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GoalStatusWidget(
          goal: goal,
          complete: complete,
          isActive: isActive,
          showLabel: false,
        ),
        const SizedBox(width: 12.0),
        Expanded(
          child: Text(
            goal.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.0,
              height: 1.2,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        if (isTop)
          const SizedBox(
            width: GoalHeaderConstants.chevronSlot,
            child: Icon(Icons.expand_less),
          ),
      ],
    );
  }
}
