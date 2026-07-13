import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// Regression coverage for #7114 ("Remove extra space for course modules
/// without activities"): an objective/module with no activities must be dropped
/// from the course-objectives list, not rendered as a header over an empty
/// fixed-height activity-card row.
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
  );

  QuestObjectiveGroup objGroup(String id, {required bool withActivities}) =>
      QuestObjectiveGroup(
        objective: LearningObjective(id: id, objective: 'obj-$id'),
        activities: withActivities
            ? [QuestActivity(activityId: 'a-$id', plan: plan('a-$id'))]
            : const [],
      );

  group('objectiveGroupsWithActivities (#7114)', () {
    test('drops activity-less objectives, keeps the rest in order', () {
      final result = objectiveGroupsWithActivities([
        objGroup('1', withActivities: true),
        objGroup('2', withActivities: false),
        objGroup('3', withActivities: true),
      ]);
      expect(result.map((g) => g.objective.id).toList(), ['1', '3']);
    });

    test('null (still loading / no data) yields an empty list', () {
      expect(objectiveGroupsWithActivities(null), isEmpty);
    });

    test('an all-empty outline yields empty (falls through to the '
        '"no activities" message)', () {
      expect(
        objectiveGroupsWithActivities([objGroup('1', withActivities: false)]),
        isEmpty,
      );
    });
  });
}
