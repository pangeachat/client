import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/routes/world/map_context.dart';

/// A joined course's map shows one Mission: the one picked in the URL when it
/// is one of the course's Missions, else the course's current Mission — the
/// same fallback the course page's circles make, so the map is never left
/// empty by a stale or filtered-out `?mission=`.
void main() {
  const progress = QuestProgress(
    courseId: '!course:example.org',
    questId: 'quest-1',
    orderedMissionIds: ['m1', 'm2', 'm3', 'unscored'],
    anchorMissionId: 'm2',
    indexByMission: {'m1': 0, 'm2': 1, 'm3': 2, 'unscored': 3},
    rollup: {
      'm1': MissionProgress(xp: 300, threshold: 300),
      'm2': MissionProgress(xp: 40, threshold: 300),
      'm3': MissionProgress(xp: 0, threshold: 300),
    },
  );

  CourseMapContext scope({String? missionId}) => CourseMapContext(
    'plan-1',
    spaceId: '!course:example.org',
    missionId: missionId,
  );

  test('no picked Mission shows the current one', () {
    expect(scope().selectedMissionIn(progress), 'm2');
  });

  test('a picked Mission of the course is shown', () {
    expect(scope(missionId: 'm3').selectedMissionIn(progress), 'm3');
    expect(scope(missionId: 'm1').selectedMissionIn(progress), 'm1');
  });

  test('an unknown picked Mission falls back to the current one', () {
    expect(scope(missionId: 'stale').selectedMissionIn(progress), 'm2');
  });

  test('a Mission with no activities is not one the map can show', () {
    expect(scope(missionId: 'unscored').selectedMissionIn(progress), 'm2');
  });

  test('nothing is selected before the course progression resolves', () {
    expect(scope(missionId: 'm3').selectedMissionIn(null), isNull);
  });
}
