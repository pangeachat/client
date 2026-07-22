import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_goal_header_card.dart';

/// Read-only goal header for the start page and the summary
class ActivityGoalsDropdown extends StatefulWidget {
  final List<ActivityRoleGoal>? goals;
  final Set<String> completedGoalIds;
  final bool startCollapsed;

  const ActivityGoalsDropdown({
    super.key,
    required this.goals,
    required this.completedGoalIds,
    this.startCollapsed = false,
  });

  @override
  State<ActivityGoalsDropdown> createState() => _ActivityGoalsDropdownState();
}

class _ActivityGoalsDropdownState extends State<ActivityGoalsDropdown> {
  bool _visible = false;
  bool showDropdown = true;
  List<ActivityRoleGoal>? _displayGoals;

  @override
  void initState() {
    super.initState();
    _displayGoals = widget.goals;
    _visible = widget.goals != null && widget.goals!.isNotEmpty;
    showDropdown = !widget.startCollapsed;
  }

  @override
  void didUpdateWidget(covariant ActivityGoalsDropdown old) {
    super.didUpdateWidget(old);
    if (old.goals != widget.goals) {
      final hasGoals = widget.goals != null && widget.goals!.isNotEmpty;
      if (hasGoals) {
        // Selecting (or switching) a role opens the goals automatically.
        setState(() {
          _displayGoals = widget.goals;
          _visible = true;
          showDropdown = true;
        });
      } else {
        setState(() => _visible = false);
        Future.delayed(FluffyThemes.animationDuration, () {
          if (mounted) setState(() => _displayGoals = null);
        });
      }
    }
  }

  void _toggleShowDropdown() => setState(() => showDropdown = !showDropdown);

  bool _isGoalCompleted(ActivityRoleGoal goal) =>
      widget.completedGoalIds.contains(goal.id);

  @override
  Widget build(BuildContext context) {
    final goals = _displayGoals ?? const <ActivityRoleGoal>[];
    final active = firstIncompleteGoal(goals, _isGoalCompleted);
    final allComplete = goals.isNotEmpty && active == null;

    return ClipRect(
      child: AnimatedAlign(
        duration: FluffyThemes.animationDuration,
        curve: Curves.easeInOut,
        heightFactor: _visible ? 1.0 : 0.0,
        alignment: Alignment.topCenter,
        child: goals.isEmpty
            ? const SizedBox(width: double.infinity)
            : ActivityGoalHeaderCard(
                showDropdown: showDropdown,
                isComplete: allComplete,
                collapsed: ActivityDropdownHeader(
                  goals: goals,
                  isGoalCompleted: _isGoalCompleted,
                  onToggle: _toggleShowDropdown,
                  activeGoalId: active?.id,
                  subtitle: allComplete
                      ? null
                      : goalHeaderLabel(active?.description ?? ''),
                ),
                expanded: ActivityDropdownContent(
                  goals: goals,
                  isGoalCompleted: _isGoalCompleted,
                  onToggle: _toggleShowDropdown,
                  activeGoalId: active?.id,
                ),
              ),
      ),
    );
  }
}
