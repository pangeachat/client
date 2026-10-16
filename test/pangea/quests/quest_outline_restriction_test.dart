import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../courses/course_missions_fixtures.dart';

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
      // The word list practice credits the Mission by follows the same
      // restriction, case-folded (#9420).
      expect(projected.lemmasByLo['lo-1'], {'hola'});
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
  });

  /// The course's own copy (content-studio): one pure transform every reader
  /// goes through. With a copy the course reads only it — its Can-Dos, its
  /// order, its activities; without one, behaviour is today's pin rule.
  group('QuestOutline.forRules (course copy)', () {
    CourseListRules withCopy(
      Map<String, List<String>> missions, {
      Map<String, String> notes = const {},
      Map<String, String> dueAt = const {},
      String? timeZone,
    }) => CourseListRules(
      missions: CourseMissionsEvent.tryParse(
        copyContent(missions, notes: notes, dueAt: dueAt, timeZone: timeZone),
      ),
    );

    QuestOutline threeMissions() => outline({
      'lo-1': [activity('a1'), activity('a2')],
      'lo-2': [activity('b1'), activity('b2')],
      'lo-3': [activity('c1')],
    });

    test('reorders and restricts to the copy, and orderedLoIds follows it', () {
      final shown = threeMissions().forRules(
        withCopy({
          'lo-3': ['c1'],
          'lo-1': ['a2'],
        }),
      );
      expect(shown.groups.map((g) => g.objective.id), ['lo-3', 'lo-1']);
      expect(idsOf(shown, 'lo-1'), {'a2'});
      // The trap: toCourseLoOutline orders by the quest's sequence, so the
      // sequence must follow the copy too.
      expect(shown.quest.learningObjectiveIds, ['lo-3', 'lo-1']);
      final projected = shown.toCourseLoOutline();
      expect(projected.orderedLoIds, ['lo-3', 'lo-1']);
      expect(projected.activityIdsByLo, {
        'lo-3': {'c1'},
        'lo-1': {'a2'},
      });
    });

    test('an activity the library no longer returns drops; a Can-Do the quest '
        'no longer carries drops; an emptied Can-Do stays with none', () {
      final shown = threeMissions().forRules(
        withCopy({
          'lo-gone': ['x1'],
          'lo-2': ['b2', 'withdrawn'],
          'lo-3': ['withdrawn'],
        }),
      );
      expect(shown.groups.map((g) => g.objective.id), ['lo-2', 'lo-3']);
      expect(idsOf(shown, 'lo-2'), {'b2'});
      expect(idsOf(shown, 'lo-3'), isEmpty);
    });

    test('a Can-Do\'s activities keep the library order, whatever order '
        'the copy lists them in', () {
      // Writers snapshot from different listings (the app's creation copy,
      // the dashboard's publish and the backfill), so the copy's activity
      // order is not a teacher choice in v1. Reading it as a set keeps what a
      // student sees unchanged when a copy is written.
      final shown = threeMissions().forRules(
        withCopy({
          'lo-1': ['a2', 'a1'],
        }),
      );
      expect(shown.groups.single.activities.map((a) => a.activityId).toList(), [
        'a1',
        'a2',
      ]);
    });

    test('ignores the pins when a copy exists', () {
      final shown = threeMissions().forRules(
        CourseListRules(
          missions: withCopy({
            'lo-1': ['a1', 'a2'],
          }).missions,
          pins: {
            'lo-1': ['a1'],
          },
        ),
      );
      expect(idsOf(shown, 'lo-1'), {'a1', 'a2'});
    });

    test('carries the note, due date and course time zone', () {
      final shown = threeMissions().forRules(
        withCopy(
          {
            'lo-1': ['a1'],
            'lo-2': ['b1'],
          },
          notes: {'lo-1': 'Lesson 6'},
          dueAt: {'lo-1': '2026-10-20T21:00:00Z'},
          timeZone: 'America/New_York',
        ),
      );
      final pacing = shown.groups.first.pacing!;
      expect(pacing.note, 'Lesson 6');
      expect(pacing.dueAt, DateTime.utc(2026, 10, 20, 21));
      expect(pacing.timeZone, 'America/New_York');
      expect(shown.groups.last.pacing, isNull);
    });

    test('never mutates the shared source outline', () {
      final source = threeMissions();
      source.forRules(
        withCopy({
          'lo-2': ['b1'],
        }),
      );
      expect(source.groups.map((g) => g.objective.id), [
        'lo-1',
        'lo-2',
        'lo-3',
      ]);
      expect(source.quest.learningObjectiveIds, ['lo-1', 'lo-2', 'lo-3']);
      expect(idsOf(source, 'lo-2'), {'b1', 'b2'});
    });

    test('no copy is identical to today: restrictedTo(pins)', () {
      final source = threeMissions();
      const pins = {
        'lo-1': ['a1'],
        'lo-3': ['stale'],
      };
      final today = source.restrictedTo(pins).toCourseLoOutline();
      final shown = source
          .forRules(const CourseListRules(pins: pins))
          .toCourseLoOutline();
      expect(shown.orderedLoIds, today.orderedLoIds);
      expect(shown.activityIdsByLo, today.activityIdsByLo);
      expect(shown.lemmasByLo, today.lemmasByLo);
      expect(identical(source.forRules(CourseListRules.none), source), isTrue);
    });

    test('the next Mission follows the copy order', () {
      final resolution = resolveProgression(
        outlines: [
          threeMissions()
              .forRules(
                withCopy({
                  'lo-3': ['c1'],
                  'lo-1': ['a1'],
                }),
              )
              .toCourseLoOutline(),
        ],
        xpByActivity: const {},
      );
      expect(resolution.forCourse('q1')!.anchorMissionId, 'lo-3');
      expect(resolution.forCourse('q1')!.rollup.keys, {'lo-3', 'lo-1'});
    });
  });
}
