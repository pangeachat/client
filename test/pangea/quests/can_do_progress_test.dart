import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/can_do_progress.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';

/// A course's Missions as its progress record carries them (client#9643): the
/// ring's XP, the split's parts, and the star.
void main() {
  ActivityPlanModel plan(String id, String lemma) => ActivityPlanModel(
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
    vocab: [Vocab(lemma: lemma, pos: 'noun')],
    activityId: id,
    roles: const {},
  );

  QuestObjectiveGroup group(
    String loId, {
    List<QuestActivity> activities = const [],
    List<QuestActivity> hiddenActivities = const [],
  }) => QuestObjectiveGroup(
    objective: LearningObjective(id: loId, objective: loId),
    activities: activities,
    hiddenActivities: hiddenActivities,
  );

  final outline = QuestOutline(
    quest: QuestPlan(
      id: 'q1',
      name: '',
      description: '',
      targetLanguage: 'es',
      sequence: [
        for (final loId in ['shown', 'hidden'])
          QuestObjectiveStep(
            objective: LearningObjective(id: loId, objective: loId),
            wasMinted: false,
          ),
      ],
    ),
    groups: [
      group(
        'shown',
        activities: [QuestActivity(activityId: 'a1', plan: plan('a1', 'casa'))],
      ),
      group(
        'hidden',
        hiddenActivities: [
          QuestActivity(activityId: 'b1', plan: plan('b1', 'viaje')),
        ],
      ),
    ],
  );

  tearDown(() => MissionXpCache.instance.seed());

  test(
    'every Mission the course carries, with the ring\'s XP and star',
    () async {
      final client = await getTestClient();
      MissionXpCache.instance.seed(
        practiceXpByLemma: {'casa': 1200, 'viaje': 2000},
      );
      final canDos = client.canDoProgress(
        outline,
        xpToComplete: 1000,
        xpByActivity: const {'a1': 150},
        byActivity: const {'a1': MissionXpBreakdown(chat: 100, goals: 50)},
      );

      final shown = canDos['shown']!;
      expect(shown.xp, 1350);
      expect(shown.breakdown.total, shown.xp);
      expect(shown.breakdown.practice, 1200);
      expect(shown.completed, isTrue);

      // Its activity is hidden, so the course page gives it no star, however
      // much XP its words have earned.
      final hidden = canDos['hidden']!;
      expect(hidden.xp, 2000);
      expect(hidden.completed, isFalse);
      await client.dispose();
    },
  );

  test(
    'a recorded completion stays complete after the threshold rises',
    () async {
      final client = await getTestClient();
      final canDos = client.canDoProgress(
        outline,
        xpToComplete: 1000,
        xpByActivity: const {'a1': 150},
        byActivity: const {'a1': MissionXpBreakdown(chat: 100, goals: 50)},
        recorded: {
          'shown': CanDoProgress(
            xp: 150,
            breakdown: const MissionXpBreakdown(chat: 100, goals: 50),
            completed: true,
            firstCompletedAt: DateTime.utc(2026, 10, 20),
            xpToCompleteAtFirstCompletion: 100,
          ),
        },
      );
      expect(canDos['shown']!.xp, 150);
      expect(canDos['shown']!.completed, isTrue);
      await client.dispose();
    },
  );

  test('below the threshold is not complete', () async {
    final client = await getTestClient();
    final canDos = client.canDoProgress(
      outline,
      xpToComplete: 1000,
      xpByActivity: const {'a1': 150},
      byActivity: const {'a1': MissionXpBreakdown(chat: 100, goals: 50)},
    );
    expect(canDos['shown']!.xp, 150);
    expect(canDos['shown']!.completed, isFalse);
    await client.dispose();
  });
}
