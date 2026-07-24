import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goal_header_card.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ActivityStatsMenu extends StatelessWidget with GoalProgressMixin {
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

  bool _isGoalCompleted(ActivityRoleGoal goal) =>
      room.isOwnGoalCompleted(goal.id, goalSlug: goal.goalSlug);

  void _toggleShowDropdown() => setShowDropdown(!visibilityNotifier.value);

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

    return ValueListenableBuilder(
      valueListenable: activeGoalNotifier,
      builder: (context, activeGoal, _) {
        final goals = _goals;
        final allComplete = goals.isNotEmpty && room.hasCompletedOwnGoals;
        final active = allComplete
            ? null
            : (activeGoal ?? firstIncompleteGoal(goals, _isGoalCompleted));
        final hasActions = _showEndForMe || _showEndForAll || _showWaitNotDone;

        // A role with no goals — a role-less admin, or a legacy/unresolved plan —
        // still needs the end-activity buttons; otherwise there's nothing to show.
        if (goals.isEmpty && !hasActions) return const SizedBox.shrink();

        return ValueListenableBuilder(
          valueListenable: visibilityNotifier,
          builder: (context, showDropdown, _) {
            final ownRoleDone = room.hasCompletedRole || _activityComplete;
            final Widget? subtitle = ownRoleDone
                ? null
                : _showDoneButtonHint
                ? _DoneButton(onPressed: () => _finishActivityForMe(context))
                : active != null
                ? GoalHeaderLabel(active.description)
                : null;

            final collapsed = goals.isEmpty
                ? ActivityDropdownHeader(
                    goals: goals,
                    isGoalCompleted: _isGoalCompleted,
                    onToggle: _toggleShowDropdown,
                    title: L10n.of(context).activityActions,
                  )
                : ActivityDropdownHeader(
                    goals: goals,
                    isGoalCompleted: _isGoalCompleted,
                    onToggle: _toggleShowDropdown,
                    activeGoalId: ownRoleDone ? null : active?.id,
                    subtitle: subtitle,
                  );

            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: showDropdown ? 0 : null,
              child: Stack(
                children: [
                  if (showDropdown)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setShowDropdown(false),
                        child: ColoredBox(color: Colors.black.withAlpha(100)),
                      ),
                    ),
                  ActivityGoalHeaderCard(
                    showDropdown: showDropdown,
                    isComplete: allComplete,
                    collapsed: collapsed,
                    expanded: ActivityDropdownContent(
                      goals: goals,
                      isGoalCompleted: _isGoalCompleted,
                      onToggle: _toggleShowDropdown,
                      title: goals.isEmpty
                          ? L10n.of(context).activityActions
                          : null,
                      activeGoalId: active?.id,
                      showEndForAll: _showEndForAll,
                      showEndForMe: _showEndForMe,
                      showWaitNotDone: _showWaitNotDone,
                      hasCompletedOwnGoals: room.hasCompletedOwnGoals,
                      haveAllRolesCompletedAllGoals:
                          room.haveAllRolesCompletedAllGoals,
                      finishActivityForAll: () =>
                          _finishActivityForAll(context),
                      finishActivityForMe: () => _finishActivityForMe(context),
                      continueActivity: room.continueActivity,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DoneButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DoneButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppConfig.goldByTheme(context),
        foregroundColor: theme.brightness == Brightness.light
            ? null
            : theme.colorScheme.surface,
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
    );
  }
}
