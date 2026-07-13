import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_content_container.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_dropdown_header.dart';

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

  void setShowDropdown(bool value) => setState(() => showDropdown = value);

  bool _isGoalCompleted(ActivityRoleGoal goal) =>
      widget.completedGoalIds.contains(goal.id);

  @override
  Widget build(BuildContext context) {
    final goals = _displayGoals ?? [];
    final visibleGoal = goals.isNotEmpty ? goals.first : null;
    final remainingGoals = goals.length > 1
        ? goals.skip(1).toList()
        : <ActivityRoleGoal>[];

    return ClipRect(
      child: AnimatedAlign(
        duration: FluffyThemes.animationDuration,
        curve: Curves.easeInOut,
        heightFactor: _visible ? 1.0 : 0.0,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (visibleGoal != null)
              ActivityDropdownHeader(
                goal: visibleGoal,
                isGoalCompleted: _isGoalCompleted(visibleGoal),
                toggleShowDropdown: _toggleShowDropdown,
                trailing: remainingGoals.isNotEmpty
                    ? Icon(showDropdown ? Icons.expand_less : Icons.expand_more)
                    : null,
                animateGoalTransitions: false,
              ),
            if (remainingGoals.isNotEmpty)
              ActivityDropdownContentContainer(
                showDropdown: showDropdown,
                setShowDropdown: setShowDropdown,
                child: ActivityDropdownContent(
                  goals: remainingGoals,
                  isGoalCompleted: _isGoalCompleted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
