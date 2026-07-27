import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';

/// Shared goal-progress lookups for the widgets that drive the goal header.
mixin GoalProgressMixin {
  /// The first goal not yet completed, or null when every goal is done.
  ActivityRoleGoal? firstIncompleteGoal(
    List<ActivityRoleGoal> goals,
    bool Function(ActivityRoleGoal) isComplete,
  ) {
    for (final goal in goals) {
      if (!isComplete(goal)) return goal;
    }
    return null;
  }
}
