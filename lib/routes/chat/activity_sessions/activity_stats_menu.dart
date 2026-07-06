import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content_container.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ActivityStatsMenu extends StatelessWidget {
  final ValueNotifier<bool> visibilityNotifier;
  final void Function(bool) setShowDropdown;
  final ValueNotifier<ActivityRoleGoal?> activeGoalNotifier;
  final Room room;

  const ActivityStatsMenu({
    required this.visibilityNotifier,
    required this.setShowDropdown,
    required this.room,
    required this.activeGoalNotifier,
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

  bool get _showWaitNotDone =>
      !_activityComplete && room.hasPickedRole && room.hasCompletedRole;

  bool get _showEndForMe =>
      !_activityComplete && room.hasPickedRole && !room.hasCompletedRole;

  bool get _showEndForAll =>
      !_activityComplete && room.isRoomAdmin && !_isTwoPersonBotActivity;

  bool get _showDoneButtonHint => _showEndForMe && room.hasCompletedOwnGoals;

  List<ActivityRoleGoal> get _goals => room.ownRole?.allGoals ?? [];

  List<ActivityRoleGoal> _remainingGoals(String? activeGoalId) =>
      _goals.where((g) => g.id != activeGoalId).toList();

  bool _isGoalCompleted(ActivityRoleGoal goal) =>
      room.isOwnGoalCompleted(goal.id, goalSlug: goal.goalSlug);

  void _toggleShowDropdown() {
    final value = visibilityNotifier.value;
    setShowDropdown(!value);
  }

  Future<void> _finishActivityForMe(BuildContext context) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: room.finishActivity,
    );

    if (!resp.isError) {
      setShowDropdown(false);
    }
  }

  Future<void> _finishActivityForAll(BuildContext context) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: room.finishActivityForAll,
    );

    if (!resp.isError) {
      setShowDropdown(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!room.showActivityChatUI) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: activeGoalNotifier,
      builder: (context, activeGoal, _) {
        // Show the live goal, or fall back to the last goal when none is active,
        // so the current-goal header doesn't vanish. (Our branch had regressed
        // this to gate the whole header on `activeGoal != null`; main always
        // shows a goal via this fallback. See the main↔branch reconciliation.)
        final visibleGoal = activeGoal ?? room.ownRole?.allGoals.lastOrNull;
        final remainingGoals = _remainingGoals(visibleGoal?.id);
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
                      if (visibleGoal != null)
                        ActivityDropdownHeader(
                          goal: visibleGoal,
                          isGoalCompleted: _isGoalCompleted(visibleGoal),
                          toggleShowDropdown: _toggleShowDropdown,
                          trailing: _showDoneButtonHint && !showDropdown
                              ? InkWell(
                                  onTap: () => _finishActivityForMe(context),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 6.0,
                                      horizontal: 12.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppConfig.goldByTheme(context),
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                    ),
                                    child: Text(
                                      L10n.of(context).completeActivityButton,
                                      style:
                                          theme.brightness == Brightness.light
                                          ? null
                                          : TextStyle(
                                              color: theme.colorScheme.surface,
                                            ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      if (remainingGoals.isNotEmpty)
                        ActivityDropdownContentContainer(
                          showDropdown: showDropdown,
                          setShowDropdown: setShowDropdown,
                          child: child!,
                        ),
                    ],
                  ),
                  if (showDropdown)
                    Expanded(
                      child: GestureDetector(
                        onTap: _toggleShowDropdown,
                        child: Container(color: Colors.black.withAlpha(100)),
                      ),
                    ),
                ],
              ),
            );
          },
          child: ActivityDropdownContent(
            goals: remainingGoals,
            isGoalCompleted: _isGoalCompleted,
            showEndForAll: _showEndForAll,
            showEndForMe: _showEndForMe,
            showWaitNotDone: _showWaitNotDone,
            hasCompletedOwnGoals: room.hasCompletedOwnGoals,
            haveAllRolesCompletedAllGoals: room.haveAllRolesCompletedAllGoals,
            finishActivityForAll: () => _finishActivityForAll(context),
            finishActivityForMe: () => _finishActivityForMe(context),
            continueActivity: room.continueActivity,
          ),
        );
      },
    );
  }
}
