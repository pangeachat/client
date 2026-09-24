import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/activity_v2_mapper.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

void main() {
  // The choreo `GET /choreo/quests/{id}/activities` entry shape. Canonical-only
  // filtering and hidden/private gating are server-side now (org activities
  // doc § Ownership, visibility, and removal) — these tests pin the client's
  // parse of that response into cards and plans.
  Map<String, dynamic> entry(String activityId, {List<String>? refs}) => {
    'plan': {
      'activity_id': activityId,
      'title': 'En el Mercado',
      'description': 'A visitor orders fruit at a market.',
      'learning_objective': 'Greet politely and ask for prices.',
      'mode': 'Roleplay',
      'cefr_level': 'A2',
      'l2': 'es',
      'original_l1': 'en',
      'coordinates': [-99.1332, 19.4326],
      'user_id': '@teacher:pangea.chat',
      'roles': [
        {'role_id': 'cliente', 'name': 'Cliente'},
        {'role_id': 'vendedor', 'name': 'Vendedor'},
      ],
      'goals': [
        {
          'goal': 'Saludar al vendedor',
          'role_ids': ['cliente', 'vendedor'],
          'phase': 'opener',
        },
      ],
      'vocab': [
        {'lemma': 'fruta', 'pos': 'NOUN'},
      ],
      'media': [],
    },
    'version_id': 'sig-$activityId',
    'learning_objective_refs': refs ?? ['lo-1'],
  };

  group('QuestRepo.questActivityEntriesFromJson', () {
    test('parses the activities list from the response body', () {
      final entries = QuestRepo.questActivityEntriesFromJson({
        'activities': [entry('act-1'), entry('act-2')],
        'private_included': true,
      });
      expect(entries, hasLength(2));
      expect((entries.first['plan'] as Map)['activity_id'], 'act-1');
    });

    test('tolerates malformed bodies', () {
      expect(QuestRepo.questActivityEntriesFromJson(null), isEmpty);
      expect(QuestRepo.questActivityEntriesFromJson([]), isEmpty);
      expect(
        QuestRepo.questActivityEntriesFromJson({'activities': 'x'}),
        isEmpty,
      );
    });
  });

  group('QuestRepo.cmsDocShapeFromEntry', () {
    test('adapts an entry to the shared card parser', () {
      final card = QuestActivityCard.fromJson(
        QuestRepo.cmsDocShapeFromEntry(entry('act-1', refs: ['lo-1', 'lo-2'])),
      );
      expect(card.activityId, 'act-1');
      expect(card.l2, 'es');
      expect(card.learningObjectiveRefs, ['lo-1', 'lo-2']);
      expect(card.point, isNotNull);
      expect(card.roleCount, 2);
    });

    test('adapts an entry to the shared plan parser with a version pin', () {
      final plan = activityPlanFromV2(
        QuestRepo.cmsDocShapeFromEntry(entry('act-1')),
      );
      expect(plan.activityId, 'act-1');
      // The choreo content-signature rides through so a session opened from
      // the outline pins its version without a refetch.
      expect(plan.versionId, 'sig-act-1');
      expect(plan.roles, isNotNull);
      expect(plan.roles.length, 2);
    });
  });

  group('QuestRepo.dedupeByActivityId', () {
    test('keeps the first row per activity_id', () {
      final rows = [
        (id: 'a', tag: 1),
        (id: 'b', tag: 2),
        (id: 'a', tag: 3),
        (id: 'c', tag: 4),
        (id: 'b', tag: 5),
      ];
      final unique = QuestRepo.dedupeByActivityId(rows, (r) => r.id);
      expect(unique.map((r) => r.tag), [1, 2, 4]);
    });

    test('passes unique rows through unchanged', () {
      final rows = [(id: 'a'), (id: 'b')];
      expect(QuestRepo.dedupeByActivityId(rows, (r) => r.id), rows);
    });
  });

  group('QuestRepo.groupActivitiesByLo', () {
    // #3045: an activity satisfying several of the quest's Missions is
    // many-to-many by design, but must render once, not once per Mission.
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
      roles: const {},
    );

    QuestActivity activity(String id) =>
        QuestActivity(activityId: id, plan: plan(id));

    QuestObjectiveStep step(String loId) => QuestObjectiveStep(
      objective: LearningObjective(id: loId, objective: loId),
      wasMinted: false,
    );

    test(
      'keeps a shared activity only under the first Mission it satisfies',
      () {
        final shared = activity('act-shared');
        final groups = QuestRepo.groupActivitiesByLo(
          sequence: [step('lo-1'), step('lo-2')],
          learningObjectives: const {},
          byLo: {
            'lo-1': [shared],
            'lo-2': [shared, activity('act-2-only')],
          },
        );

        expect(groups[0].activities.map((a) => a.activityId), ['act-shared']);
        expect(groups[1].activities.map((a) => a.activityId), ['act-2-only']);
      },
    );

    test('a Mission whose only activity was claimed earlier is left empty', () {
      final shared = activity('act-shared');
      final groups = QuestRepo.groupActivitiesByLo(
        sequence: [step('lo-1'), step('lo-2')],
        learningObjectives: const {},
        byLo: {
          'lo-1': [shared],
          'lo-2': [shared],
        },
      );

      expect(groups[1].activities, isEmpty);
    });

    test('leaves unrelated Missions and single-Mission activities alone', () {
      final a1 = activity('a1');
      final b1 = activity('b1');
      final groups = QuestRepo.groupActivitiesByLo(
        sequence: [step('lo-1'), step('lo-2')],
        learningObjectives: const {},
        byLo: {
          'lo-1': [a1],
          'lo-2': [b1],
        },
      );

      expect(groups[0].activities.map((a) => a.activityId), ['a1']);
      expect(groups[1].activities.map((a) => a.activityId), ['b1']);
    });
  });
}
