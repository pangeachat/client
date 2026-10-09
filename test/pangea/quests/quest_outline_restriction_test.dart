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
  ActivityPlanModel plan(String id, {List<String> vocab = const []}) =>
      ActivityPlanModel(
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
        vocab: [for (final lemma in vocab) Vocab(lemma: lemma, pos: 'NOUN')],
        activityId: id,
      );

  QuestActivity activity(String id, {List<String> vocab = const []}) =>
      QuestActivity(
        activityId: id,
        plan: plan(id, vocab: vocab),
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

    test('projection derives filtered activity and vocab maps', () {
      final o = outline({
        'lo-1': [
          activity('a1', vocab: ['Hola']),
          activity('a2', vocab: ['adiós']),
        ],
      });
      final projected = o
          .restrictedTo({
            'lo-1': ['a1'],
          })
          .toCourseLoOutline(xpToComplete: 500);
      expect(projected.activityIdsByLo['lo-1'], {'a1'});
      // The Mission's vocabulary follows its pinned activities, lower-cased.
      expect(projected.vocabLemmasByLo['lo-1'], {'hola'});
      expect(projected.xpToComplete, 500);
    });
  });

  group('restricted outline through resolveProgression', () {
    test('XP on an off-pin activity does not count toward the Mission', () {
      final o = outline({
        'lo-1': [activity('a1'), activity('a2')],
      });
      final resolution = resolveProgression(
        outlines: [
          o.restrictedTo({
            'lo-1': ['a1'],
          }).toCourseLoOutline(),
        ],
        xpByActivity: {'a1': 80, 'a2': 500},
      );
      expect(resolution.forCourse('q1')!.rollup['lo-1']!.xp, 80);
    });

    test("practice XP on an off-pin activity's vocabulary does not count", () {
      final o = outline({
        'lo-1': [
          activity('a1', vocab: ['hola']),
          activity('a2', vocab: ['adiós']),
        ],
      });
      final resolution = resolveProgression(
        outlines: [
          o.restrictedTo({
            'lo-1': ['a1'],
          }).toCourseLoOutline(),
        ],
        xpByActivity: const {},
        xpByLemma: {'hola': 40, 'adiós': 500},
      );
      expect(resolution.forCourse('q1')!.rollup['lo-1']!.xp, 40);
    });
  });
}
