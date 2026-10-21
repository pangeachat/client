import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/activity_v2_mapper.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';

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

  group('QuestRepo.questMissionsFromJson', () {
    // The outline read's `missions`: each statement already in the display
    // language the read asked for (#8577). The quest row keeps the order;
    // this map supplies the text.
    test('parses the missions list keyed by id', () {
      final missions = QuestRepo.questMissionsFromJson({
        'missions': [
          {
            'lo_id': 'lo-1',
            'objective': 'Peut saluer quelqu\'un.',
            'source_l1': 'en',
            'localized': true,
            'theme': 'daily life',
            'cefr_level': 'A1',
            'scale_id': 'just_chatting',
          },
          {
            'lo_id': 'lo-2',
            'objective': 'Can order a coffee.',
            'source_l1': 'en',
            'localized': false,
          },
        ],
        'activities': [],
      });
      expect(missions.keys, ['lo-1', 'lo-2']);
      expect(missions['lo-1']!.objective, 'Peut saluer quelqu\'un.');
      expect(missions['lo-1']!.theme, 'daily life');
      expect(missions['lo-1']!.cefr, 'A1');
      expect(missions['lo-2']!.theme, isNull);
    });

    test(
      'drops an entry with no id or no statement, and tolerates malformed bodies',
      () {
        final missions = QuestRepo.questMissionsFromJson({
          'missions': [
            {'lo_id': 'lo-1'},
            {'objective': 'orphan'},
            'x',
            {'lo_id': 'lo-2', 'objective': 'Can order a coffee.'},
          ],
        });
        expect(missions.keys, ['lo-2']);
        expect(QuestRepo.questMissionsFromJson(null), isEmpty);
        expect(QuestRepo.questMissionsFromJson({'missions': 'x'}), isEmpty);
        // A body from a choreo that predates the field: no missions, no error.
        expect(QuestRepo.questMissionsFromJson({'activities': []}), isEmpty);
      },
    );
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

    test('passes the row-level starter flag through to the card (#9561)', () {
      final starter = QuestActivityCard.fromJson(
        QuestRepo.cmsDocShapeFromEntry({...entry('act-1'), 'starter': true}),
      );
      expect(starter.starter, isTrue);
      // An entry without the flag (an older choreo) is not a starter.
      expect(
        QuestActivityCard.fromJson(
          QuestRepo.cmsDocShapeFromEntry(entry('act-2')),
        ).starter,
        isFalse,
      );
      // TEMPORARY with QuestActivityCard.temporaryStarterActivityIds: an
      // allowlisted id with no flag reads as a starter on this path too.
      expect(
        QuestActivityCard.fromJson(
          QuestRepo.cmsDocShapeFromEntry(
            entry(QuestActivityCard.temporaryStarterActivityIds.first),
          ),
        ).starter,
        isTrue,
      );
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
}
