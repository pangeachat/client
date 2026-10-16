import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objective_circles.dart';

/// "Class location" (#9420 prototype): where the teacher's due dates put the
/// class — the first Mission still due, else the last dated one.
void main() {
  final now = DateTime.utc(2026, 10, 15, 12);

  QuestObjectiveGroup group(String id, {DateTime? dueAt}) =>
      QuestObjectiveGroup(
        objective: LearningObjective(id: id, objective: id),
        activities: const [],
        pacing: dueAt == null ? null : MissionPacing(dueAt: dueAt),
      );

  test('no due dates: no class location', () {
    expect(
      CourseObjectiveCircles.classLocationIndex([group('a'), group('b')], now),
      isNull,
    );
  });

  test('the first Mission still due, in plan order', () {
    final groups = [
      group('a', dueAt: now.subtract(const Duration(days: 3))),
      group('b'),
      group('c', dueAt: now.add(const Duration(days: 2))),
      group('d', dueAt: now.add(const Duration(days: 9))),
    ];
    expect(CourseObjectiveCircles.classLocationIndex(groups, now), 2);
  });

  test('every dated Mission past: the last dated one', () {
    final groups = [
      group('a', dueAt: now.subtract(const Duration(days: 9))),
      group('b', dueAt: now.subtract(const Duration(days: 2))),
      group('c'),
    ];
    expect(CourseObjectiveCircles.classLocationIndex(groups, now), 1);
  });
}
