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
  });
}
