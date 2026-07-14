// One player's earnable stars per activity: their role's goal count. Uniform
// across roles by generation; min across roles for older plans (permissive).
// The single home is ActivityPlanModel.earnableStars — card star rows, the
// map's large card, and the Mission threshold clamp all read it. Design:
// quests.instructions.md + org activities doc (goal-progression invariants).

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

void main() {
  ActivityPlanRequest req() => ActivityPlanRequest(
    topic: 'jobs',
    mode: 'Roleplay',
    objective: 'introduce yourself',
    media: MediaEnum.nan,
    cefrLevel: LanguageLevelTypeEnum.a1,
    languageOfInstructions: 'en',
    targetLanguage: 'de',
    numberOfParticipants: 2,
  );

  ActivityRole role(String id, int goalCount) => ActivityRole(
    id: id,
    name: id,
    goal: null,
    goals: [
      for (var i = 0; i < goalCount; i++)
        ActivityRoleGoal(id: '$id-g$i', description: 'goal $i'),
    ],
  );

  ActivityPlanModel plan(Map<String, ActivityRole> roles) => ActivityPlanModel(
    req: req(),
    title: 'Speed-Dating Interview',
    learningObjective: 'lo',
    instructions: 'i',
    vocab: const [],
    activityId: 'act-1',
    roles: roles,
  );

  group('ActivityPlanModel.earnableStars', () {
    test('uniform goal counts read that count', () {
      final p = plan({'a': role('a', 4), 'b': role('b', 4)});
      expect(p.earnableStars, 4);
    });

    test('differing counts (pre-uniform plans) take the min across roles', () {
      final p = plan({'a': role('a', 4), 'b': role('b', 3)});
      expect(p.earnableStars, 3);
    });

    test('a plan with no roles earns nothing', () {
      final p = plan(const {});
      expect(p.earnableStars, 0);
    });

    test('a legacy single-string goal counts as one', () {
      final legacy = ActivityRole(
        id: 'a',
        name: 'a',
        goal: 'say hi',
        goals: const [],
      );
      final p = plan({'a': legacy, 'b': role('b', 3)});
      expect(p.earnableStars, 1);
    });
  });
}
