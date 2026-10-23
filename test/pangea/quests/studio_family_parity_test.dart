import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The parity fixture shared byte-for-byte with admin-dash-api
/// (`studio-family-parity.json`, CONTRACT-V2): each case is a course record, a
/// listing with family ids, and sessions; the expected shown outline and
/// per-student totals are what BOTH readers must produce. Here the cases run
/// through the real client path: record parse -> [QuestOutline.forRules] ->
/// the per-member best-session reduction -> [resolveProgression].
void main() {
  final fixture =
      jsonDecode(
            File(
              'test/pangea/quests/fixtures/studio-family-parity.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

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
          for (var i = 0; i < 30; i++)
            ActivityRoleGoal(id: '$id-g$i', description: 'g$i'),
        ],
      ),
    },
  );

  /// The course as the client reads it: the library listing (every activity
  /// with its family) grouped under the Can-Dos whose record names it, shown
  /// through the record.
  QuestOutline shownOutline(Map<String, dynamic> testCase) {
    final record = testCase['record'] as Map<String, dynamic>;
    final missions = (record['missions'] as List).cast<Map<String, dynamic>>();
    final copy = CourseMissionsEvent.tryParse({
      'version': 1,
      'revision': 1,
      'missions': missions,
      if ((record['removed_missions'] as List).isNotEmpty)
        'removed_missions': record['removed_missions'],
    })!;
    final listing = (testCase['listing'] as List).cast<Map<String, dynamic>>();
    final family = {
      for (final l in listing)
        l['activity_id'] as String: (l['family_ids'] as List).cast<String>(),
    };
    final outline = QuestOutline(
      quest: QuestPlan(
        id: 'q1',
        name: '',
        description: '',
        targetLanguage: 'es',
        sequence: [
          for (final m in missions)
            QuestObjectiveStep(
              objective: LearningObjective(
                id: m['lo_id'] as String,
                objective: '',
              ),
              wasMinted: false,
            ),
        ],
      ),
      groups: [
        for (final m in missions)
          QuestObjectiveGroup(
            objective: LearningObjective(
              id: m['lo_id'] as String,
              objective: '',
            ),
            activities: [
              for (final id in family.keys)
                if ([
                  ...(m['activity_ids'] as List),
                  ...(m['removed_activity_ids'] as List),
                ].contains(id))
                  QuestActivity(activityId: id, plan: plan(id)),
            ],
          ),
      ],
      familyIdsByActivity: family,
    );
    return outline.forRules(CourseListRules(missions: copy));
  }

  for (final testCase in cases) {
    final name = testCase['name'] as String;
    final expected = testCase['expect'] as Map<String, dynamic>;

    group(name, () {
      final outline = shownOutline(testCase);
      final courseOutline = outline.toCourseLoOutline();
      final sessions = (testCase['sessions'] as List)
          .cast<Map<String, dynamic>>();
      final students = (expected['students'] as Map).cast<String, dynamic>();

      test('shows exactly the expected activities per Can-Do', () {
        expect(
          {
            for (final g in outline.groups)
              g.objective.id: g.activities.map((a) => a.activityId).toList(),
          },
          {
            for (final e in (expected['shown'] as Map).entries)
              e.key as String: (e.value as List).cast<String>(),
          },
        );
      });

      for (final entry in students.entries) {
        final student = entry.key;
        final want = entry.value as Map<String, dynamic>;
        final own = sessions.where((s) => s['student'] == student).toList();

        // Stars (goal checkmarks): best session per member, the reduction
        // userStarsByActivity applies to the learner's own session rooms.
        final stars = bestStarsByActivity([
          for (final s in own)
            (activityId: s['activity_id'] as String, stars: s['stars'] as int),
        ]);
        // XP: saved sessions summed per member, the reduction
        // userXpByActivity applies.
        final xp = sumXpByActivity([
          for (final s in own)
            (activityId: s['activity_id'] as String, xp: s['xp'] as int),
        ]);

        final wantMissions = (want['missions'] as Map).cast<String, dynamic>();
        final wantTotal = want['course_total'] as Map<String, dynamic>;

        test('$student: Can-Do stars', () {
          expect(creditedByMission(courseOutline, stars), {
            for (final e in wantMissions.entries)
              e.key: (e.value as Map)['stars'],
          });
        });

        // The real Mission XP rollup, whatever the threshold.
        test('$student: Can-Do XP', () {
          final rollup =
              resolveProgression(
                outlines: [courseOutline],
                xpByActivity: xp,
              ).forCourse(courseOutline.courseId)?.rollup ??
              const {};
          expect(
            {for (final e in rollup.entries) e.key: e.value.xp},
            {
              for (final e in wantMissions.entries)
                e.key: (e.value as Map)['xp'],
            },
          );
          expect(creditedByMission(courseOutline, xp), {
            for (final e in wantMissions.entries) e.key: (e.value as Map)['xp'],
          });
        });

        test('$student: course total', () {
          expect(creditedCourseTotal(courseOutline, stars), wantTotal['stars']);
          expect(creditedCourseTotal(courseOutline, xp), wantTotal['xp']);
        });
      }
    });
  }

  test('the contract fixture has 13 cases', () {
    expect(cases, hasLength(13));
  });
}
