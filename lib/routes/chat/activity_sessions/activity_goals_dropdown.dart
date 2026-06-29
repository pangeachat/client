import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';

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
  bool _innerExpanded = true;
  List<ActivityRoleGoal>? _displayGoals;

  @override
  void initState() {
    super.initState();
    _displayGoals = widget.goals;
    _visible = widget.goals != null && widget.goals!.isNotEmpty;
    _innerExpanded = !widget.startCollapsed;
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
          _innerExpanded = true;
        });
      } else {
        setState(() => _visible = false);
        Future.delayed(FluffyThemes.animationDuration, () {
          if (mounted) setState(() => _displayGoals = null);
        });
      }
    }
  }

  void _toggleVisiblity() => setState(() => _innerExpanded = !_innerExpanded);

  @override
  Widget build(BuildContext context) {
    final goals = _displayGoals ?? [];
    final theme = Theme.of(context);
    final visible = goals.isNotEmpty ? goals.first : null;
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
            if (visible != null)
              InkWell(
                onTap: _toggleVisiblity,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  height: 55.0,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: theme.dividerColor)),
                    color: theme.colorScheme.surface,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GoalStatusWidget(
                          goal: visible,
                          complete: widget.completedGoalIds.contains(
                            visible.id,
                          ),
                          maxLines: _innerExpanded ? null : 2,
                        ),
                      ),
                      if (remainingGoals.isNotEmpty)
                        Icon(
                          _innerExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                    ],
                  ),
                ),
              ),
            if (remainingGoals.isNotEmpty)
              ClipRect(
                child: AnimatedAlign(
                  duration: FluffyThemes.animationDuration,
                  curve: Curves.easeInOut,
                  heightFactor: _innerExpanded ? 1.0 : 0.0,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      if (d.delta.dy < -2) {
                        setState(() => _innerExpanded = false);
                      }
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxHeight =
                            MediaQuery.of(context).size.height * 0.7;
                        return ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxHeight),
                          child: SingleChildScrollView(
                            child: Container(
                              width: double.infinity,
                              color: theme.colorScheme.surface,
                              padding: const EdgeInsets.fromLTRB(
                                12.0,
                                12.0,
                                12.0,
                                24.0,
                              ),
                              child: Column(
                                spacing: 16.0,
                                mainAxisSize: MainAxisSize.min,
                                children: remainingGoals
                                    .map(
                                      (g) => GoalStatusWidget(
                                        goal: g,
                                        complete: widget.completedGoalIds
                                            .contains(g.id),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
