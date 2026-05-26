import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ActivityStatsMenu extends StatelessWidget {
  final ValueNotifier<bool> visibilityNotifier;
  final VoidCallback toggleVisibility;
  final Room room;

  const ActivityStatsMenu({
    required this.visibilityNotifier,
    required this.toggleVisibility,
    required this.room,
    super.key,
  });

  bool get _isTwoPersonBotActivity {
    final roles = room.activityRoles?.roles;
    final assignedRoles = room.assignedRoles;
    if (roles == null || assignedRoles == null) return false;

    return roles.length == 2 &&
        assignedRoles.values.any(
          (role) => role.userId == BotName.byEnvironment,
        );
  }

  bool get _activityComplete => room.isActivityFinished;

  bool get _showEndForMe =>
      !_activityComplete && room.hasPickedRole && !room.hasCompletedRole;

  bool get _showEndForAll =>
      !_activityComplete && room.isRoomAdmin && !_isTwoPersonBotActivity;

  Future<void> _finishActivityForMe(BuildContext context) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: room.finishActivity,
    );

    if (!resp.isError) {
      toggleVisibility();
    }
  }

  Future<void> _finishActivityForAll(BuildContext context) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: room.finishActivityForAll,
    );

    if (!resp.isError) {
      toggleVisibility();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!room.showActivityChatUI) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    final goals = room.ownRole?.allGoals ?? [];

    // TODO ORCHESTRATOR: show active goal instead of first goal
    final currentGoal = goals.firstOrNull;
    final remainingGoals = goals.skip(1).toList();

    return ValueListenableBuilder(
      valueListenable: visibilityNotifier,
      builder: (context, showDropdown, child) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: showDropdown ? 0 : null,
          child: Column(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentGoal != null)
                    InkWell(
                      onTap: _activityComplete ? null : toggleVisibility,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.0),
                        height: 50.0,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: theme.dividerColor),
                          ),
                          color: theme.colorScheme.surface,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GoalStatusWidget(
                                goal: currentGoal,
                                complete: room.isGoalCompleted(currentGoal.id),
                                starTarget: ActivitySessionConstants
                                    .goalMenuStarTargetId,
                              ),
                            ),
                            if (!_activityComplete && room.hasCompletedAllGoals)
                              InkWell(
                                onTap: toggleVisibility,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 6.0,
                                    horizontal: 12.0,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.brightness == Brightness.light
                                        ? AppConfig.gold
                                        : AppConfig.goldLight,
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius,
                                    ),
                                  ),
                                  child: Text(
                                    L10n.of(context).completeActivityButton,
                                    style: TextStyle(
                                      color: theme.colorScheme.surface,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ClipRect(
                    child: AnimatedAlign(
                      duration: FluffyThemes.animationDuration,
                      curve: Curves.easeInOut,
                      heightFactor: showDropdown ? 1.0 : 0.0,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          if (details.delta.dy < -2) {
                            toggleVisibility();
                          }
                        },
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
              if (showDropdown)
                Expanded(
                  child: GestureDetector(
                    onTap: toggleVisibility,
                    child: Container(color: Colors.black.withAlpha(100)),
                  ),
                ),
            ],
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = MediaQuery.of(context).size.height * 0.7;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: theme.colorScheme.surface),
                padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 24.0),
                child: Column(
                  spacing: 16.0,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (remainingGoals.isNotEmpty)
                      Column(
                        spacing: 16.0,
                        children: [
                          ...remainingGoals.map(
                            (g) => GoalStatusWidget(
                              goal: g,
                              complete: room.isGoalCompleted(g.id),
                            ),
                          ),
                        ],
                      ),
                    if (_showEndForMe)
                      ElevatedButton(
                        onPressed: () => _finishActivityForMe(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
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
                    if (_showEndForAll)
                      ElevatedButton(
                        onPressed: () => _finishActivityForAll(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.errorContainer,
                          foregroundColor: theme.colorScheme.onErrorContainer,
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
      ),
    );
  }
}
