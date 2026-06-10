import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/pangea/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_vocab_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ActivityStatsMenu extends StatefulWidget {
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

  @override
  ActivityStatsMenuState createState() => ActivityStatsMenuState();
}

class ActivityStatsMenuState extends State<ActivityStatsMenu> {
  ActivityRoleGoal? _currentGoal;

  @override
  void initState() {
    super.initState();
    _setCurrentGoal();
    widget.activeGoalNotifier.addListener(_setCurrentGoal);
  }

  @override
  void dispose() {
    widget.activeGoalNotifier.removeListener(_setCurrentGoal);
    super.dispose();
  }

  bool get _isTwoPersonBotActivity {
    final roles = widget.room.activityRoles?.roles;
    final assignedRoles = widget.room.assignedRoles;
    if (roles == null || assignedRoles == null) return false;

    return roles.length == 2 &&
        assignedRoles.values.any(
          (role) => role.userId == BotName.byEnvironment,
        );
  }

  bool get _activityComplete => widget.room.isActivityFinished;

  bool get _showWaitNotDone =>
      !_activityComplete &&
      widget.room.hasPickedRole &&
      widget.room.hasCompletedRole;

  bool get _showEndForMe =>
      !_activityComplete &&
      widget.room.hasPickedRole &&
      !widget.room.hasCompletedRole;

  bool get _showEndForAll =>
      !_activityComplete && widget.room.isRoomAdmin && !_isTwoPersonBotActivity;

  bool get _showDoneButtonHint =>
      _showEndForMe && widget.room.hasCompletedOwnGoals;

  List<ActivityRoleGoal> get _goals => widget.room.ownRole?.allGoals ?? [];

  List<ActivityRoleGoal> get _remainingGoals =>
      _goals.where((g) => g.id != _currentGoal?.id).toList();

  void _setCurrentGoal() {
    final currentGoal = widget.room.currentGoal;
    if (currentGoal == _currentGoal) return;
    if (mounted) {
      setState(() => _currentGoal = currentGoal);
    }
  }

  void _toggleVisibility() {
    final value = widget.visibilityNotifier.value;
    widget.setVisibility(!value);
  }

  Future<void> _finishActivityForMe() async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: widget.room.finishActivity,
    );

    if (!resp.isError) {
      widget.setVisibility(false);
    }
  }

  Future<void> _finishActivityForAll() async {
    final resp = await showFutureLoadingDialog(
      context: context,
      future: widget.room.finishActivityForAll,
    );

    if (!resp.isError) {
      widget.setVisibility(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.room.showActivityChatUI) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final activity = widget.room.activityPlan;

    final currentGoal = _currentGoal;
    final remainingGoals = _remainingGoals;

    final goldColor = theme.brightness == Brightness.light
        ? AppConfig.gold
        : AppConfig.goldLight;

    return ValueListenableBuilder(
      valueListenable: widget.visibilityNotifier,
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
                        child: Row(
                          children: [
                            Expanded(
                              child: GoalStatusWidget(
                                goal: currentGoal,
                                complete: widget.room.isOwnGoalCompleted(
                                  currentGoal.id,
                                ),
                                starTarget: ActivitySessionConstants
                                    .goalMenuStarTargetId,
                              ),
                            ),
                            if (_showDoneButtonHint && !showDropdown)
                              InkWell(
                                onTap: _finishActivityForMe,
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
                                    L10n.of(context).completeActivityButton,
                                    style: theme.brightness == Brightness.light
                                        ? null
                                        : TextStyle(
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
                            widget.setVisibility(false);
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
                                complete: widget.room.isOwnGoalCompleted(g.id),
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
                        usedVocab: widget.usedVocab,
                        activityLangCode: activity.req.targetLanguage,
                      ),
                    if (_showWaitNotDone)
                      ElevatedButton(
                        onPressed: widget.room.continueActivity,
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
                        onPressed: _finishActivityForMe,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.room.hasCompletedOwnGoals
                              ? goldColor
                              : theme.colorScheme.primaryContainer,
                          foregroundColor: theme.brightness == Brightness.light
                              ? null
                              : widget.room.hasCompletedOwnGoals
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
                        onPressed: _finishActivityForAll,
                        style: ElevatedButton.styleFrom(
                          side: BorderSide(
                            color: widget.room.haveAllRolesCompletedAllGoals
                                ? goldColor
                                : theme.brightness == Brightness.light
                                ? theme.colorScheme.primary.withAlpha(120)
                                : theme.colorScheme.primaryContainer,
                            width: 2,
                          ),
                          foregroundColor:
                              widget.room.haveAllRolesCompletedAllGoals
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
  }
}
