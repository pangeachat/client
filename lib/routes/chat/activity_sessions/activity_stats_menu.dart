import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_vocab_widget.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ActivityStatsMenu extends StatelessWidget {
  final ValueNotifier<bool> visibilityNotifier;
  final void Function(bool) setVisibility;
  final ValueNotifier<Set<String>> usedVocab;
  final ValueNotifier<ActivityRoleGoal?> activeGoalNotifier;
  final Room room;

  const ActivityStatsMenu({
    required this.visibilityNotifier,
    required this.setVisibility,
    required this.usedVocab,
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

  void _toggleVisibility() {
    final value = visibilityNotifier.value;
    setVisibility(!value);
  }

  Future<void> _finishActivityForMe(BuildContext context) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: room.finishActivity,
    );

    if (!resp.isError) {
      setVisibility(false);
    }
  }

  Future<void> _finishActivityForAll(BuildContext context) async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: room.finishActivityForAll,
    );

    if (!resp.isError) {
      setVisibility(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!room.showActivityChatUI) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final goldColor = theme.brightness == Brightness.light
        ? AppConfig.gold
        : AppConfig.goldLight;

    final isColumnMode = FluffyThemes.isColumnMode(context);
    final activity = room.activityPlan;

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
                        InkWell(
                          onTap: _toggleVisibility,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12.0),
                            height: 55.0,
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: theme.dividerColor),
                              ),
                              color: theme.colorScheme.surface,
                            ),
                            child: AnimatedSwitcher(
                              duration: FluffyThemes.animationDuration,
                              transitionBuilder: (child, animation) {
                                final isCurrent =
                                    child.key == ValueKey(visibleGoal.id);

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
                                  children: [
                                    ...previousChildren,
                                    ?currentChild,
                                  ],
                                );
                              },
                              child: Row(
                                key: ValueKey(visibleGoal.id),
                                children: [
                                  Expanded(
                                    child: GoalStatusWidget(
                                      goal: visibleGoal,
                                      complete: room.isOwnGoalCompleted(
                                        visibleGoal.id,
                                      ),
                                      starTarget:
                                          ActivitySessionConstants.goalMenuStarTargetId(
                                            visibleGoal.id,
                                          ),
                                    ),
                                  ),
                                  if (_showDoneButtonHint && !showDropdown)
                                    InkWell(
                                      onTap: () =>
                                          _finishActivityForMe(context),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 6.0,
                                          horizontal: 12.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: goldColor,
                                          borderRadius: BorderRadius.circular(
                                            AppConfig.borderRadius,
                                          ),
                                        ),
                                        child: Text(
                                          L10n.of(
                                            context,
                                          ).completeActivityButton,
                                          style:
                                              theme.brightness ==
                                                  Brightness.light
                                              ? null
                                              : TextStyle(
                                                  color:
                                                      theme.colorScheme.surface,
                                                ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ClipRect(
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedAlign(
                          duration: FluffyThemes.animationDuration,
                          curve: Curves.easeInOut,
                          heightFactor: showDropdown ? 1.0 : 0.0,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              if (details.delta.dy < -2) {
                                setVisibility(false);
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
                        onTap: _toggleVisibility,
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
                    color: theme.colorScheme.surface,
                    padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 24.0),
                    child: Column(
                      spacing: 16.0,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (remainingGoals.isNotEmpty)
                          Column(
                            spacing: 16.0,
                            children: remainingGoals
                                .map(
                                  (g) => GoalStatusWidget(
                                    goal: g,
                                    complete: room.isOwnGoalCompleted(g.id),
                                  ),
                                )
                                .toList(),
                          ),
                        if (activity != null)
                          ActivityVocabWidget(
                            key: ValueKey(
                              "activity-stats-menu-${activity.activityId}",
                            ),
                            vocab: activity.vocab,
                            langCode: activity.req.targetLanguage,
                            targetId: "activity-stats-menu-vocab",
                            usedVocab: usedVocab,
                            activityLangCode: activity.req.targetLanguage,
                          ),
                        if (_showWaitNotDone)
                          ElevatedButton(
                            onPressed: room.continueActivity,
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
                        if (_showEndForMe)
                          ElevatedButton(
                            onPressed: () => _finishActivityForMe(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: room.hasCompletedOwnGoals
                                  ? goldColor
                                  : theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.brightness == Brightness.light
                                  ? null
                                  : room.hasCompletedOwnGoals
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
                        if (_showEndForAll)
                          ElevatedButton(
                            onPressed: () => _finishActivityForAll(context),
                            style: ElevatedButton.styleFrom(
                              side: BorderSide(
                                color: room.haveAllRolesCompletedAllGoals
                                    ? goldColor
                                    : theme.brightness == Brightness.light
                                    ? theme.colorScheme.primary.withAlpha(120)
                                    : theme.colorScheme.primaryContainer,
                                width: 2,
                              ),
                              foregroundColor:
                                  room.haveAllRolesCompletedAllGoals
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
          ),
        );
      },
    );
  }
}
