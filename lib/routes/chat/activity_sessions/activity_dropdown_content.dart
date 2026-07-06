import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

class ActivityDropdownContent extends StatelessWidget {
  final List<ActivityRoleGoal> goals;
  final bool Function(ActivityRoleGoal) isGoalCompleted;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = MediaQuery.of(context).size.height * 0.7;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 24.0),
              child: Column(
                spacing: 16.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (goals.isNotEmpty)
                    Column(
                      spacing: 16.0,
                      children: goals
                          .map(
                            (g) => GoalStatusWidget(
                              goal: g,
                              complete: isGoalCompleted(g),
                            ),
                          )
                          .toList(),
                    ),
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
                            style: TextStyle(
                              fontSize: isColumnMode ? 16.0 : 12.0,
                            ),
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
                            style: TextStyle(
                              fontSize: isColumnMode ? 16.0 : 12.0,
                            ),
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
                            style: TextStyle(
                              fontSize: isColumnMode ? 16.0 : 12.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
