import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/activity_sessions/goal_progress_mixin.dart';

class _Progress with GoalProgressMixin {}

/// The active goal is the first one still unfinished, in the goals' fixed
/// order (activity-session.instructions.md, "The goal header"): finishing a
/// later goal leaves an earlier unfinished one active.
void main() {
  const goals = [
    ActivityRoleGoal(id: 'g1', description: 'Greet'),
    ActivityRoleGoal(id: 'g2', description: 'Ask where they are from'),
    ActivityRoleGoal(id: 'g3', description: 'Say goodbye'),
  ];
  final progress = _Progress();

  ActivityRoleGoal? activeWith(Set<String> done) =>
      progress.firstIncompleteGoal(goals, (g) => done.contains(g.id));

  test('with nothing done the first goal is active', () {
    expect(activeWith({})?.id, 'g1');
  });

  test('finishing the second goal leaves the first active', () {
    expect(activeWith({'g2'})?.id, 'g1');
  });

  test('then finishing the first hands active to the third', () {
    expect(activeWith({'g1', 'g2'})?.id, 'g3');
  });

  test('with every goal done none is active', () {
    expect(activeWith({'g1', 'g2', 'g3'}), isNull);
  });
}
