import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The quest-plan display fields the course info chips read (#7976). They moved
/// off `CoursePlanModel` — whose plan-level `topicIds.length` counted Missions
/// the learner never sees — so the language and level chips now render from the
/// quest itself and must keep reading identically.
void main() {
  Map<String, dynamic> questJson({String? cefr, String language = 'ko'}) => {
    'id': 'quest-1',
    'req': {
      'target_language': language,
      'target_l1': 'en',
      'target_cefr': ?cefr,
    },
    'res': {
      'name': 'Plan it like a pro',
      'description': 'Plan a trip.',
      'learning_objective_sequence': const [],
    },
  };

  group('QuestPlan.cefrLevel', () {
    test('parses the quest-plan CEFR string', () {
      expect(
        QuestPlan.fromJson(questJson(cefr: 'B1')).cefrLevel,
        LanguageLevelTypeEnum.b1,
      );
    });

    test(
      'a missing CEFR falls back to the enum default rather than throwing',
      () {
        expect(
          QuestPlan.fromJson(questJson()).cefrLevel,
          LanguageLevelTypeEnum.a1,
        );
      },
    );
  });

  group('QuestPlan.targetLanguageDisplay', () {
    test('uppercases the raw code when the language store has no entry', () {
      expect(
        QuestPlan.fromJson(questJson(language: 'ko')).targetLanguageDisplay,
        'KO',
      );
    });

    test(
      'an absent target language degrades to an empty chip, not a crash',
      () {
        expect(
          QuestPlan.fromJson(questJson(language: '')).targetLanguageDisplay,
          '',
        );
      },
    );
  });
}
