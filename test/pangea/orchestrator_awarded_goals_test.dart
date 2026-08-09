import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_output.dart';

void main() {
  group('OrchestratorAwardedGoals', () {
    test('parses per-role awards shape', () {
      final goals = OrchestratorAwardedGoals.fromJson({
        'awards': {
          'guest': ['order_dish', 'propose_toast'],
          'host': ['welcome_guest'],
        },
      });

      expect(goals.isGoalCompletedForRole('guest', 'order_dish'), isTrue);
      expect(goals.isGoalCompletedForRole('host', 'welcome_guest'), isTrue);
      // A shared goal completes independently per role: guest earning
      // propose_toast does not credit the host.
      expect(goals.isGoalCompletedForRole('host', 'propose_toast'), isFalse);
      expect(goals.isGoalCompletedForRole('ghost', 'order_dish'), isFalse);
    });

    test('parses pre-per-role flat shape as legacy ids for any role', () {
      // Old rooms carry {"goal_ids": [...]}; a flat id counts for any
      // role that declares the goal (callers only ask about ids from a
      // role's own goals list), matching the bot's expansion semantics.
      final goals = OrchestratorAwardedGoals.fromJson({
        'goal_ids': ['propose_toast'],
      });

      expect(goals.awards, isEmpty);
      expect(goals.isGoalCompletedForRole('guest', 'propose_toast'), isTrue);
      expect(goals.isGoalCompletedForRole('host', 'propose_toast'), isTrue);
      expect(goals.isGoalCompletedForRole('guest', 'order_dish'), isFalse);
    });

    test('round-trips per-role shape through json', () {
      final goals = OrchestratorAwardedGoals.fromJson({
        'awards': {
          'guest': ['order_dish'],
        },
      });
      final reparsed = OrchestratorAwardedGoals.fromJson(goals.toJson());
      expect(reparsed.isGoalCompletedForRole('guest', 'order_dish'), isTrue);
      expect(reparsed.isGoalCompletedForRole('host', 'order_dish'), isFalse);
    });

    test('matches on goal_slug, with legacy id fallback', () {
      // The bot now awards on the content-derived slug.
      final slugAwarded = OrchestratorAwardedGoals.fromJson({
        'awards': {
          'guest': ['content-slug-1'],
        },
      });
      expect(
        slugAwarded.isGoalCompletedForRole(
          'guest',
          'cms-id-1',
          goalSlug: 'content-slug-1',
        ),
        isTrue,
      );
      // A goal whose slug was not awarded is not complete.
      expect(
        slugAwarded.isGoalCompletedForRole(
          'guest',
          'other-id',
          goalSlug: 'other-slug',
        ),
        isFalse,
      );
      // Migration fallback: an award still keyed on the old Payload id renders
      // when the goal carries a slug the bot hasn't re-awarded yet.
      final idAwarded = OrchestratorAwardedGoals.fromJson({
        'awards': {
          'guest': ['cms-id-1'],
        },
      });
      expect(
        idAwarded.isGoalCompletedForRole(
          'guest',
          'cms-id-1',
          goalSlug: 'content-slug-1',
        ),
        isTrue,
      );
    });
  });

  group('OrchestratorOutput goal_completion', () {
    test('parses per-role buckets', () {
      final output = OrchestratorOutput.fromJson({
        'based_on_event_id': r'$evt',
        'goal_completion': [
          {
            'role_id': 'guest',
            'goal_ids': ['order_dish'],
          },
        ],
        'suggestions': [],
        'flag': null,
      });

      expect(output.goalCompletion, hasLength(1));
      expect(output.goalCompletion.first.roleId, 'guest');
      expect(output.goalCompletion.first.goalIds, ['order_dish']);
    });

    test('tolerates the old flat shape during rollout', () {
      // An old bot may still broadcast flat string ids; they cannot be
      // attributed to a role, so they are ignored rather than throwing
      // (a throw would break suggestion display for the whole event).
      final output = OrchestratorOutput.fromJson({
        'based_on_event_id': r'$evt',
        'goal_completion': ['order_dish'],
        'suggestions': [
          {
            'role_id': 'guest',
            'suggestions': [
              {'text': 'Hola', 'type': 'best'},
            ],
          },
        ],
        'flag': null,
      });

      expect(output.goalCompletion, isEmpty);
      expect(output.suggestionsByRoleId('guest'), hasLength(1));
    });
  });
}
