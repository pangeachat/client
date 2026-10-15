import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/activity_family.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';

/// Where the family crediting reaches the readers beyond the parity fixture:
/// the Mission rollup the course panel and the world map band read, the
/// per-activity numbers on cards and pins, and — the safety rail — that a
/// course with no copy reads exactly as it did before copies existed.
void main() {
  ActivityPlanModel plan(String id) => ActivityPlanModel(
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
          for (var i = 0; i < 4; i++)
            ActivityRoleGoal(id: '$id-g$i', description: 'g$i'),
        ],
      ),
    },
  );

  QuestOutline library(
    Map<String, List<String>> activitiesByLo, {
    Map<String, List<String>> family = const {},
  }) => QuestOutline(
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
      for (final e in activitiesByLo.entries)
        QuestObjectiveGroup(
          objective: LearningObjective(id: e.key, objective: e.key),
          activities: [
            for (final id in e.value)
              QuestActivity(activityId: id, plan: plan(id)),
          ],
        ),
    ],
    familyIdsByActivity: family,
  );

  CourseListRules record(
    Map<String, List<String>> shown, {
    Map<String, List<String>> removed = const {},
  }) => CourseListRules(
    missions: CourseMissionsEvent.tryParse({
      'version': 1,
      'revision': 1,
      'missions': [
        for (final e in shown.entries)
          {
            'lo_id': e.key,
            'activity_ids': e.value,
            'removed_activity_ids': ?removed[e.key],
          },
      ],
    }),
  );

  group('a course with no copy reads exactly as before', () {
    final source = library({
      'lo1': ['a1', 'a2'],
      'lo2': ['b1'],
    });
    final rules = record({
      'lo1': ['a1', 'a2'],
      'lo2': ['b1'],
    });

    test('its outline carries no credit', () {
      final shown = source.forRules(rules);
      expect(shown.credit.isEmpty, isTrue);
      expect(shown.toCourseLoOutline().credit.isEmpty, isTrue);
    });

    test('a listing that names only each activity as its own family is the '
        'same', () {
      final withFamilies = library(
        {
          'lo1': ['a1', 'a2'],
          'lo2': ['b1'],
        },
        family: {
          'a1': ['a1'],
          'a2': ['a2'],
          'b1': ['b1'],
        },
      );
      expect(withFamilies.forRules(rules).credit.isEmpty, isTrue);
    });

    test('the rollup is the plain sum over the shown activities', () {
      const stars = {'a1': 2, 'a2': 3, 'b1': 1, 'elsewhere': 9};
      final resolution = resolveProgression(
        outlines: [source.forRules(rules).toCourseLoOutline()],
        starsByActivity: stars,
      );
      final rollup = resolution.forCourse('q1')!.rollup;
      expect(rollup['lo1']!.stars, 5);
      expect(rollup['lo2']!.stars, 1);
    });

    test('the cache hands the same star map back untouched', () {
      final cache = JoinedObjectiveCache();
      const stars = {'a1': 2};
      expect(identical(cache.creditedStars(stars), stars), isTrue);
    });
  });

  group('best session per activity', () {
    test('keeps the highest and an entry for every activity played', () {
      expect(
        bestStarsByActivity([
          (activityId: 'a1', stars: 1),
          (activityId: 'a1', stars: 3),
          (activityId: 'a1', stars: 2),
          (activityId: 'a2', stars: 0),
        ]),
        {'a1': 3, 'a2': 0},
      );
    });
  });

  group('with a swapped copy', () {
    // lo1 shows the copy c1; the original a1 is hidden. The learner earned 2
    // stars on a1 before the swap and 1 on c1 after.
    final listing = library(
      {
        'lo1': ['a1', 'c1', 'a2'],
      },
      family: {
        'a1': ['a1', 'c1'],
        'c1': ['a1', 'c1'],
      },
    );
    final shown = listing.forRules(
      record(
        {
          'lo1': ['c1', 'a2'],
        },
        removed: {
          'lo1': ['a1'],
        },
      ),
    );
    const stars = {'a1': 2, 'c1': 1, 'a2': 1};

    test('the Can-Do rollup sums the family onto the shown copy', () {
      final rollup = resolveProgression(
        outlines: [shown.toCourseLoOutline()],
        starsByActivity: stars,
      ).forCourse('q1')!.rollup;
      expect(rollup['lo1']!.stars, 4);
    });

    test('credit survives the joined-course cache re-key', () async {
      final cache = JoinedObjectiveCache();
      await cache.rebuild([
        'room1',
      ], outlineOf: (_) async => shown.toCourseLoOutline());
      expect(cache.outlines.single.courseId, 'room1');
      expect(cache.outlines.single.credit.isEmpty, isFalse);
      final rollup = cache.resolution(stars).forCourse('room1')!.rollup;
      expect(rollup['lo1']!.stars, 4);
    });

    test('a card for the shown copy shows the family total', () {
      expect(shown.credit.starsFor('c1', stars), 3);
      expect(shown.credit.starsFor('a2', stars), 1);
    });

    test('the map pins show the credited stars and keep every other', () {
      final cache = JoinedObjectiveCache();
      final credited = cache.creditedStars(
        stars,
        extraOutlines: [shown.toCourseLoOutline()],
      );
      expect(credited['c1'], 3);
      // The original keeps its own stars where it is shown on its own.
      expect(credited['a1'], 2);
      expect(credited['a2'], 1);
    });

    test('the threshold clamp is bound by the shown activities only', () {
      // The hidden original adds stars to the Can-Do but no earnable ceiling.
      final outline = shown.toCourseLoOutline();
      expect(outline.earnableByActivity.keys.toSet(), {'c1', 'a2'});
    });
  });

  group('the XP hook', () {
    test('creditedByMission sums sessions per member onto the shown copy', () {
      final shown =
          library(
            {
              'lo1': ['a1', 'c1'],
            },
            family: {
              'a1': ['a1', 'c1'],
              'c1': ['a1', 'c1'],
            },
          ).forRules(
            record(
              {
                'lo1': ['c1'],
              },
              removed: {
                'lo1': ['a1'],
              },
            ),
          );
      expect(
        creditedByMission(shown.toCourseLoOutline(), {'a1': 300, 'c1': 200}),
        {'lo1': 500},
      );
    });
  });

  group('edge cases of the credit', () {
    test('a Can-Do whose activities are all hidden still reports its XP', () {
      final shown =
          library({
            'lo1': ['a1'],
            'lo2': ['b1'],
          }).forRules(
            record(
              {
                'lo1': [],
                'lo2': ['b1'],
              },
              removed: {
                'lo1': ['a1'],
              },
            ),
          );
      final outline = shown.toCourseLoOutline();
      expect(creditedByMission(outline, {'a1': 300, 'b1': 50}), {
        'lo1': 300,
        'lo2': 50,
      });
      // Nothing shows for lo1, so the panel's star rollup leaves it out.
      final rollup = resolveProgression(
        outlines: [outline],
        starsByActivity: {'a1': 2, 'b1': 1},
      ).forCourse('q1')!.rollup;
      expect(rollup.keys, ['lo2']);
      expect(creditedCourseTotal(outline, {'a1': 2, 'b1': 1}), 3);
    });

    test('a family shown in two Can-Dos credits each, like a shared '
        'activity does today', () {
      final shown =
          library(
            {
              'lo1': ['a1'],
              'lo2': ['c1'],
            },
            family: {
              'a1': ['a1', 'c1'],
              'c1': ['a1', 'c1'],
            },
          ).forRules(
            record({
              'lo1': ['a1'],
              'lo2': ['c1'],
            }),
          );
      final outline = shown.toCourseLoOutline();
      expect(creditedByMission(outline, {'a1': 2, 'c1': 1}), {
        'lo1': 3,
        'lo2': 3,
      });
      // The course counts the family once.
      expect(creditedCourseTotal(outline, {'a1': 2, 'c1': 1}), 3);
      // Both Can-Dos' cards read the family total, not one 3 and one 0.
      expect(shown.credit.starsFor('a1', {'a1': 2, 'c1': 1}), 3);
      expect(shown.credit.starsFor('c1', {'a1': 2, 'c1': 1}), 3);
    });
  });

  test('CourseLoOutline defaults to no credit', () {
    const outline = CourseLoOutline(
      courseId: 'c',
      orderedLoIds: [],
      activityIdsByLo: {},
    );
    expect(outline.credit.isEmpty, isTrue);
    expect(CourseCredit.none.family, isEmpty);
  });
}
