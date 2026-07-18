import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';

/// Card-based (hydration-free) star resolution — #7602, landed in the V6 pins
/// PR (#7714): the learner's star/super-star tier and the display star total
/// derive from the pin's thin `goals` (matched on `goal_slug`, legacy goal id
/// fallback), never from a full-plan hydration. Completion is judged against
/// the card's CURRENT content, so an owner edit that adds a goal demotes an
/// earned tier (world-map.instructions.md, "Goal Progress").
void main() {
  QuestActivityCard card({
    List<ActivityCardGoal> goals = const [],
    List<String> roleIds = const [],
  }) => QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    coordinates: const [0, 0],
    learningObjectiveRefs: const [],
    roleIds: roleIds,
    goals: goals,
  );

  ActivityCardGoal goal(
    String? slug, {
    String? id,
    List<String> roles = const ['r1'],
  }) => ActivityCardGoal(id: id, goalSlug: slug, roleIds: roles);

  OwnRoleAwards awards(String roleId, List<String> awarded) => (
    roleId: roleId,
    awards: OrchestratorAwardedGoals(awards: {roleId: awarded}),
  );

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

  group('starLevelForCard', () {
    test('null (unresolvable) when the card carries no thin goals', () {
      expect(
        starLevelForCard(card(), [
          awards('r1', ['s1']),
        ]),
        isNull,
      );
    });

    test('none with no awards', () {
      final c = card(goals: [goal('s1')]);
      expect(starLevelForCard(c, const []), ActivityStarLevel.none);
    });

    test('star once every goal of one role is awarded by slug', () {
      final c = card(
        roleIds: ['r1', 'r2'],
        goals: [
          goal('s1', roles: ['r1']),
          goal('s2', roles: ['r1']),
          goal('s3', roles: ['r2']),
        ],
      );
      final level = starLevelForCard(c, [
        awards('r1', ['s1', 's2']),
      ]);
      expect(level, ActivityStarLevel.star);
    });

    test('a partially-awarded role is not a star', () {
      final c = card(
        goals: [
          goal('s1', roles: ['r1']),
          goal('s2', roles: ['r1']),
        ],
      );
      expect(
        starLevelForCard(c, [
          awards('r1', ['s1']),
        ]),
        ActivityStarLevel.none,
      );
    });

    test('legacy goal id matches when the slug is absent', () {
      // r2 stays un-awarded so the tier reads star, isolating the id match.
      final c = card(
        roleIds: ['r1', 'r2'],
        goals: [goal(null, id: 'g1')],
      );
      expect(
        starLevelForCard(c, [
          awards('r1', ['g1']),
        ]),
        ActivityStarLevel.star,
      );
    });

    test('a goal with neither slug nor id blocks its role', () {
      final c = card(goals: [goal(null)]);
      expect(
        starLevelForCard(c, [
          awards('r1', ['anything']),
        ]),
        ActivityStarLevel.none,
      );
    });

    test('awards for a different role never complete this one', () {
      final c = card(
        goals: [
          goal('s1', roles: ['r1']),
        ],
      );
      expect(
        starLevelForCard(c, [
          awards('r2', ['s1']),
        ]),
        ActivityStarLevel.none,
      );
    });

    test('awards union across attempts (two rooms, same role)', () {
      // r2 stays un-awarded so the tier reads star, isolating the union rule.
      final c = card(
        roleIds: ['r1', 'r2'],
        goals: [
          goal('s1', roles: ['r1']),
          goal('s2', roles: ['r1']),
        ],
      );
      final level = starLevelForCard(c, [
        awards('r1', ['s1']),
        awards('r1', ['s2']),
      ]);
      expect(level, ActivityStarLevel.star);
    });

    test('super star once every role is complete', () {
      final c = card(
        roleIds: ['r1', 'r2'],
        goals: [
          goal('s1', roles: ['r1']),
          goal('s2', roles: ['r2']),
        ],
      );
      final level = starLevelForCard(c, [
        awards('r1', ['s1']),
        awards('r2', ['s2']),
      ]);
      expect(level, ActivityStarLevel.superStar);
    });

    test('a card role with no goals blocks the super star, not the star', () {
      final c = card(
        roleIds: ['r1', 'r2'],
        goals: [
          goal('s1', roles: ['r1']),
        ],
      );
      expect(
        starLevelForCard(c, [
          awards('r1', ['s1']),
        ]),
        ActivityStarLevel.star,
      );
    });

    test(
      'an owner-added goal demotes an earned tier (current content wins)',
      () {
        // The learner super-starred the 1-goal-per-role version; the owner then
        // added s3 to r1. Judged against the CURRENT card, r1 is incomplete →
        // the super star demotes to r2's plain star. Accepted 2026-07-18.
        final c = card(
          roleIds: ['r1', 'r2'],
          goals: [
            goal('s1', roles: ['r1']),
            goal('s3', roles: ['r1']),
            goal('s2', roles: ['r2']),
          ],
        );
        final level = starLevelForCard(c, [
          awards('r1', ['s1']),
          awards('r2', ['s2']),
        ]);
        expect(level, ActivityStarLevel.star);
      },
    );

    test(
      'role set falls back to the goals\' roles when the card omits roleIds',
      () {
        final c = card(
          goals: [
            goal('s1', roles: ['r1']),
            goal('s2', roles: ['r2']),
          ],
        );
        final level = starLevelForCard(c, [
          awards('r1', ['s1']),
          awards('r2', ['s2']),
        ]);
        expect(level, ActivityStarLevel.superStar);
      },
    );
  });
}
