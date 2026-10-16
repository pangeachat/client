import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';

/// A pin's display goal total derives from its thin `goals`, never from a
/// full-plan hydration.
void main() {
  QuestActivityCard card({List<ActivityCardGoal> goals = const []}) =>
      QuestActivityCard(
        activityId: 'a1',
        title: 'Test Activity',
        l2: 'es',
        coordinates: const [0, 0],
        learningObjectiveRefs: const [],
        goals: goals,
      );

  ActivityCardGoal goal(String? slug, {List<String> roles = const ['r1']}) =>
      ActivityCardGoal(goalSlug: slug, roleIds: roles);

  group('QuestActivityCard.thinStarsTotal', () {
    test('null when the card carries no thin goals', () {
      expect(card().thinStarsTotal, isNull);
    });

    test('uniform per-role counts return that count', () {
      final c = card(
        goals: [
          goal('s1', roles: ['r1']),
          goal('s2', roles: ['r1']),
          goal('s3', roles: ['r2']),
          goal('s4', roles: ['r2']),
        ],
      );
      expect(c.thinStarsTotal, 2);
    });

    test('disagreeing per-role counts fall back to the min', () {
      // Decision 2026-07-18: min across roles (supersedes the Figma Pins-v6
      // note's "average/greatest"), matching ActivityPlanModel.earnableStars.
      final c = card(
        goals: [
          goal('s1', roles: ['r1']),
          goal('s2', roles: ['r1']),
          goal('s3', roles: ['r1']),
          goal('s4', roles: ['r2']),
        ],
      );
      expect(c.thinStarsTotal, 1);
    });

    test('a goal shared across roles counts once per role', () {
      final c = card(
        goals: [
          goal('s1', roles: ['r1', 'r2']),
          goal('s2', roles: ['r1']),
        ],
      );
      // r1 has 2, r2 has 1 → min 1.
      expect(c.thinStarsTotal, 1);
    });
  });
}
