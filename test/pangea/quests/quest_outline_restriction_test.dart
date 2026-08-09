import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// Per-course activity pinning (client#7748): [QuestOutline.restrictedTo] is a
/// PURE COPY transform — the quest-outline cache is shared across courses that
/// pin the same quest, so restriction must never mutate the cached object. A
/// pin filters a Mission's activities to the pinned set; every fail-open rule
/// exists so a pin can never make a Mission unsatisfiable (org quests doc).
void main() {
  ActivityPlanModel plan(String id, {int goals = 3}) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: '',
      mode: '',
      objective: '',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a2,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: '',
    learningObjective: '',
    instructions: '',
    vocab: const [],
    activityId: id,
    roles: {
      'r1': ActivityRole(
        id: 'r1',
        name: 'r1',
        goal: null,
        goals: [
          for (var i = 0; i < goals; i++)
            ActivityRoleGoal(id: '$id-g$i', description: 'g$i'),
        ],
      ),
    },
  );

  QuestActivity activity(String id, {int goals = 3}) => QuestActivity(
    activityId: id,
    plan: plan(id, goals: goals),
  );

  QuestOutline outline(Map<String, List<QuestActivity>> activitiesByLo) =>
      QuestOutline(
        quest: QuestPlan(
          id: 'q1',
          name: '',
          description: '',
          targetLanguage: 'es',
          sequence: [
            for (final loId in activitiesByLo.keys)
              QuestObjectiveStep(
                objective: LearningObjective(id: loId, objective: loId),
                wasMinted: false,
              ),
          ],
        ),
        groups: [
          for (final entry in activitiesByLo.entries)
            QuestObjectiveGroup(
              objective: LearningObjective(id: entry.key, objective: entry.key),
              activities: entry.value,
            ),
        ],
      );

  Set<String> idsOf(QuestOutline o, String loId) => o.groups
      .firstWhere((g) => g.objective.id == loId)
      .activities
      .map((a) => a.activityId)
      .toSet();

  group('QuestOutline.restrictedTo', () {
    test('null pins leaves every group unfiltered', () {
      final o = outline({
        'lo-1': [activity('a1'), activity('a2')],
      });
      final restricted = o.restrictedTo(null);
      expect(idsOf(restricted, 'lo-1'), {'a1', 'a2'});
    });

    test('filters a pinned Mission to the pinned set', () {
      final o = outline({
        'lo-1': [activity('a1'), activity('a2'), activity('a3')],
        'lo-2': [activity('b1'), activity('b2')],
      });
      final restricted = o.restrictedTo({
        'lo-1': ['a1', 'a3'],
      });
      expect(idsOf(restricted, 'lo-1'), {'a1', 'a3'});
      // lo-2 has no pin entry — unchanged.
      expect(idsOf(restricted, 'lo-2'), {'b1', 'b2'});
    });

    test('drops stale pinned ids not in the Mission', () {
      final o = outline({
        'lo-1': [activity('a1'), activity('a2')],
      });
      final restricted = o.restrictedTo({
        'lo-1': ['a1', 'gone-activity'],
      });
      expect(idsOf(restricted, 'lo-1'), {'a1'});
    });

    test('fails open when the pin intersects to nothing', () {
      final o = outline({
        'lo-1': [activity('a1'), activity('a2')],
      });
      final restricted = o.restrictedTo({
        'lo-1': ['gone-1', 'gone-2'],
      });
      expect(idsOf(restricted, 'lo-1'), {'a1', 'a2'});
    });

    test('fails open on an empty pinned list', () {
      final o = outline({
        'lo-1': [activity('a1'), activity('a2')],
      });
      final restricted = o.restrictedTo({'lo-1': []});
      expect(idsOf(restricted, 'lo-1'), {'a1', 'a2'});
    });

    test('never mutates the source outline (shared cache safety)', () {
      final o = outline({
        'lo-1': [activity('a1'), activity('a2')],
      });
      o.restrictedTo({
        'lo-1': ['a1'],
      });
      expect(idsOf(o, 'lo-1'), {'a1', 'a2'});
    });

    test('projection derives filtered activity and earnable maps', () {
      final o = outline({
        'lo-1': [activity('a1', goals: 4), activity('a2', goals: 5)],
      });
      final projected = o.restrictedTo({
        'lo-1': ['a1'],
      }).toCourseLoOutline();
      expect(projected.activityIdsByLo['lo-1'], {'a1'});
      expect(projected.earnableByActivity.containsKey('a2'), isFalse);
      expect(projected.earnableByActivity['a1'], 4);
    });
  });

  group('restricted outline through resolveProgression', () {
    test('stars on an off-pin activity do not count toward the Mission', () {
      final o = outline({
        'lo-1': [activity('a1'), activity('a2')],
      });
      final resolution = resolveProgression(
        outlines: [
          o.restrictedTo({
            'lo-1': ['a1'],
          }).toCourseLoOutline(),
        ],
        starsByActivity: {'a1': 2, 'a2': 5},
      );
      expect(resolution.forCourse('q1')!.rollup['lo-1']!.stars, 2);
    });

    test('the effective threshold clamps to the pinned set', () {
      final o = outline({
        'lo-1': [activity('a1', goals: 4), activity('a2', goals: 6)],
      });
      final resolution = resolveProgression(
        outlines: [
          o
              .restrictedTo({
                'lo-1': ['a1'],
              })
              .toCourseLoOutline(starsToUnlock: 10),
        ],
        starsByActivity: const {},
      );
      // Unrestricted the ceiling would be 10 (4+6 = 10); pinned it is 4.
      expect(resolution.forCourse('q1')!.rollup['lo-1']!.threshold, 4);
    });
  });
}
