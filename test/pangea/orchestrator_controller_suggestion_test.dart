import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_output.dart';

/// Unit tests for the turn-based recommendation rule in
/// [OrchestratorController.suggestionToShow]. The orchestrator broadcasts one
/// room-wide event carrying a bucket per role; each client decides for itself
/// whether to render. The recommendation goes to the responder (the human who
/// did NOT just speak) in a multi-human activity, and to the lone human in a
/// single-human (participant) activity.
void main() {
  const userA = '@a:server';
  const userB = '@b:server';
  const roleA = 'roleA';
  const roleB = 'roleB';
  const eventA = r'$msgA';
  const eventB = r'$msgB';

  OrchestratorOutput outputWithBothRoles(String basedOnEventId) =>
      OrchestratorOutput.fromJson({
        'based_on_event_id': basedOnEventId,
        'goal_completion': [],
        'suggestions': [
          {
            'role_id': roleA,
            'suggestions': [
              {'text': 'A-best', 'type': 'best'},
              {'text': 'A-distractor', 'type': 'distractor'},
            ],
          },
          {
            'role_id': roleB,
            'suggestions': [
              {'text': 'B-best', 'type': 'best'},
              {'text': 'B-distractor', 'type': 'distractor'},
            ],
          },
        ],
        'flag': null,
      });

  group('OrchestratorController.suggestionToShow — 2 humans', () {
    test('A spoke last: B is prompted with B\'s bucket', () {
      final output = outputWithBothRoles(eventA);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleB,
        currentUserId: userB,
        latestMessageEventId: eventA,
        latestHumanMessageSenderId: userA,
        humanRoleCount: 2,
      );
      expect(result, isNotNull);
      expect(result!.roleId, roleB);
    });

    test('A spoke last: A is NOT prompted (the speaker)', () {
      final output = outputWithBothRoles(eventA);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleA,
        currentUserId: userA,
        latestMessageEventId: eventA,
        latestHumanMessageSenderId: userA,
        humanRoleCount: 2,
      );
      expect(result, isNull);
    });

    test('B spoke last: A is prompted with A\'s bucket', () {
      final output = outputWithBothRoles(eventB);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleA,
        currentUserId: userA,
        latestMessageEventId: eventB,
        latestHumanMessageSenderId: userB,
        humanRoleCount: 2,
      );
      expect(result, isNotNull);
      expect(result!.roleId, roleA);
    });

    test('B spoke last: B is NOT prompted (the speaker)', () {
      final output = outputWithBothRoles(eventB);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleB,
        currentUserId: userB,
        latestMessageEventId: eventB,
        latestHumanMessageSenderId: userB,
        humanRoleCount: 2,
      );
      expect(result, isNull);
    });
  });

  group(
    'OrchestratorController.suggestionToShow — single human (participant)',
    () {
      test('lone human is prompted right after their own message', () {
        final output = outputWithBothRoles(eventA);
        final result = OrchestratorController.suggestionToShow(
          output: output,
          ownRoleId: roleA,
          currentUserId: userA,
          latestMessageEventId: eventA,
          latestHumanMessageSenderId: userA, // the lone human spoke last
          humanRoleCount: 1,
        );
        expect(result, isNotNull);
        expect(result!.roleId, roleA);
      });

      test(
        'not prompted when the latest message is not the current user\'s',
        () {
          final output = outputWithBothRoles(eventB);
          final result = OrchestratorController.suggestionToShow(
            output: output,
            ownRoleId: roleA,
            currentUserId: userA,
            latestMessageEventId: eventB,
            latestHumanMessageSenderId: userB,
            humanRoleCount: 1,
          );
          expect(result, isNull);
        },
      );
    },
  );

  group('OrchestratorController.suggestionToShow — guards', () {
    test('stale output (not based on latest human message) is dropped', () {
      final output = outputWithBothRoles(
        eventA,
      ); // computed from an older event
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleB,
        currentUserId: userB,
        latestMessageEventId: eventB, // a newer human message exists
        latestHumanMessageSenderId: userA,
        humanRoleCount: 2,
      );
      expect(result, isNull);
    });

    test('no bucket for the current user\'s role returns null', () {
      final output = OrchestratorOutput.fromJson({
        'based_on_event_id': eventA,
        'goal_completion': [],
        'suggestions': [
          {
            'role_id': roleA,
            'suggestions': [
              {'text': 'A-best', 'type': 'best'},
            ],
          },
        ],
        'flag': null,
      });
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleB, // no bucket for roleB in this output
        currentUserId: userB,
        latestMessageEventId: eventA,
        latestHumanMessageSenderId: userA,
        humanRoleCount: 2,
      );
      expect(result, isNull);
    });

    test('no human messages yet (null latest) is dropped', () {
      final output = outputWithBothRoles(eventA);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleB,
        currentUserId: userB,
        latestMessageEventId: null,
        latestHumanMessageSenderId: null,
        humanRoleCount: 2,
      );
      expect(result, isNull);
    });
  });

  group('OrchestratorController.suggestionToShow — any-sender staleness', () {
    const botEvent = r'$botReply';

    test('output based on the bot reply (the latest message) is shown to the '
        'lone human', () {
      // Re-fire (choreo#2761): after the bot replies to the lone human, the
      // fresh output is based on the bot's message. The human still sent the
      // latest HUMAN message, so they are prompted.
      final output = outputWithBothRoles(botEvent);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleA,
        currentUserId: userA,
        latestMessageEventId: botEvent,
        latestHumanMessageSenderId: userA,
        humanRoleCount: 1,
      );
      expect(result, isNotNull);
      expect(result!.roleId, roleA);
    });

    test('output based on an older human message is dropped once a bot reply '
        'is the latest message', () {
      final output = outputWithBothRoles(eventA);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleA,
        currentUserId: userA,
        latestMessageEventId: botEvent, // the bot has since replied
        latestHumanMessageSenderId: userA,
        humanRoleCount: 1,
      );
      expect(result, isNull);
    });
  });

  group('OrchestratorOutput.fromJson — v2 bucket tolerance', () {
    test('reaction bucket (empty options + reaction key) is dropped', () {
      final output = OrchestratorOutput.fromJson({
        'based_on_event_id': eventA,
        'goal_completion': [],
        'suggestions': [
          {'role_id': roleA, 'suggestions': [], 'reaction': '👍'},
          {
            'role_id': roleB,
            'suggestions': [
              {'text': 'B-best', 'type': 'best'},
            ],
          },
        ],
        'flag': null,
      });
      expect(output.suggestions, hasLength(1));
      expect(output.suggestions.single.roleId, roleB);
    });

    test(
      'null options list and missing role_id are dropped, siblings kept',
      () {
        final output = OrchestratorOutput.fromJson({
          'based_on_event_id': eventA,
          'goal_completion': [
            {
              'role_id': roleA,
              'goal_ids': ['goal-1'],
            },
          ],
          'suggestions': [
            {'role_id': roleA, 'suggestions': null},
            {
              'suggestions': [
                {'text': 'no-role', 'type': 'best'},
              ],
            },
            {
              'role_id': roleB,
              'suggestions': [
                {'text': 'B-best', 'type': 'best'},
              ],
            },
          ],
          'flag': null,
        });
        expect(output.suggestions, hasLength(1));
        expect(output.suggestions.single.roleId, roleB);
        // goal_completion survives malformed sibling buckets.
        expect(output.goalCompletion, hasLength(1));
      },
    );

    test(
      'unknown option type or null text skips the entry, keeps valid ones',
      () {
        final output = OrchestratorOutput.fromJson({
          'based_on_event_id': eventA,
          'goal_completion': [],
          'suggestions': [
            {
              'role_id': roleA,
              'suggestions': [
                {'text': null, 'type': 'best'},
                {'text': 'valid', 'type': 'best'},
                {'text': 'weird', 'type': 'emoji'},
              ],
            },
          ],
          'flag': null,
        });
        expect(output.suggestions, hasLength(1));
        expect(output.suggestions.single.suggestions, hasLength(1));
        expect(output.suggestions.single.suggestions.single.text, 'valid');
      },
    );

    test('missing suggestions key parses to an empty list', () {
      final output = OrchestratorOutput.fromJson({
        'based_on_event_id': eventA,
        'goal_completion': [],
        'flag': null,
      });
      expect(output.suggestions, isEmpty);
    });
  });
}
