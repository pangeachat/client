import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';

void main() {
  group('QuestActivityCard.fromBboxCard', () {
    // Choreo source of truth:
    // 2-step-choreographer/app/handlers/activities/activity_schema.py ActivityCard
    //   activity_id / title / l2 / cefr_level / coordinates / description /
    //   learning_objective / learning_objective_refs: list[str]
    Map<String, dynamic> card() => {
      'activity_id': 'act-1',
      'title': 'En el Mercado',
      'l2': 'es',
      'cefr_level': 'A2',
      'description': 'A short scenario.',
      'learning_objective': 'Order at a market.',
      'coordinates': [-99.1332, 19.4326],
    };

    test('parses learning_objective_refs from the bbox card', () {
      final c = QuestActivityCard.fromBboxCard({
        ...card(),
        'learning_objective_refs': ['lo-a', 'lo-b'],
      });
      expect(c.activityId, 'act-1');
      expect(c.learningObjectiveRefs, ['lo-a', 'lo-b']);
      // The content-search + cefr fields still come through.
      expect(c.cefr, 'A2');
      expect(c.description, 'A short scenario.');
    });

    test('defaults refs to empty when the field is absent', () {
      final c = QuestActivityCard.fromBboxCard(card());
      expect(c.learningObjectiveRefs, isEmpty);
    });

    test('tolerates an empty refs list', () {
      final c = QuestActivityCard.fromBboxCard({
        ...card(),
        'learning_objective_refs': const [],
      });
      expect(c.learningObjectiveRefs, isEmpty);
    });

    test('parses thin roles → roleCount / roleIds', () {
      final c = QuestActivityCard.fromBboxCard({
        ...card(),
        'roles': [
          {'role_id': 'vendor'},
          {'role_id': 'customer'},
          {'role_id': 'friend'},
        ],
      });
      expect(c.roleCount, 3);
      expect(c.roleIds, ['vendor', 'customer', 'friend']);
    });

    test('parses thin goals with slug, role mapping, and phase', () {
      final c = QuestActivityCard.fromBboxCard({
        ...card(),
        'goals': [
          {
            'id': 'g1',
            'goal_slug': 'greet-slug',
            'role_ids': ['vendor', 'customer'],
            'phase': 'opener',
          },
        ],
      });
      expect(c.goals.length, 1);
      expect(c.goals.first.id, 'g1');
      expect(c.goals.first.goalSlug, 'greet-slug');
      expect(c.goals.first.roleIds, ['vendor', 'customer']);
      expect(c.goals.first.phase, 'opener');
    });

    test('parses the non-localized mode / rating / original_l1', () {
      final c = QuestActivityCard.fromBboxCard({
        ...card(),
        'mode': 'Roleplay',
        'rating_average': 4.5,
        'rating_count': 12,
        'original_l1': 'en',
      });
      expect(c.mode, 'Roleplay');
      expect(c.ratingAverage, 4.5);
      expect(c.ratingCount, 12);
      expect(c.originalL1, 'en');
    });

    test('role_count stays null when an older choreo omits roles (inert)', () {
      final c = QuestActivityCard.fromBboxCard(card());
      expect(c.roleCount, isNull);
      expect(c.roleIds, isEmpty);
      expect(c.goals, isEmpty);
    });
  });

  group('QuestActivityCard.fromJson (course path)', () {
    // The CMS-doc shape QuestRepo.cmsDocShapeFromEntry adapts a course entry
    // to: { res: { plan: {...} }, learningObjectiveRefs: [...] }. The plan node
    // is the same one activityPlanFromV2 reads its cefr_level from.
    Map<String, dynamic> doc() => {
      'res': {
        'plan': {
          'activity_id': 'act-2',
          'title': 'En la Fiesta',
          'l2': 'es',
          'cefr_level': 'B1',
          'coordinates': [-99.1332, 19.4326],
          'roles': [
            {'role_id': 'r1'},
            {'role_id': 'r2'},
          ],
        },
      },
      'learningObjectiveRefs': ['lo-a'],
    };

    test('carries the CEFR level from res.plan.cefr_level (#8243)', () {
      final c = QuestActivityCard.fromJson(doc());
      expect(c.activityId, 'act-2');
      expect(c.cefr, 'B1');
      expect(c.l2, 'es');
      expect(c.roleCount, 2);
      expect(c.learningObjectiveRefs, ['lo-a']);
    });

    test('cefr stays null when the plan omits cefr_level', () {
      final d = doc();
      (d['res'] as Map)['plan'] = {
        'activity_id': 'act-3',
        'title': 'No level',
        'l2': 'es',
        'coordinates': [0, 0],
      };
      expect(QuestActivityCard.fromJson(d).cefr, isNull);
    });
  });
}
