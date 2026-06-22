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
        latestHumanMessageEventId: eventA,
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
        latestHumanMessageEventId: eventA,
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
        latestHumanMessageEventId: eventB,
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
        latestHumanMessageEventId: eventB,
        latestHumanMessageSenderId: userB,
        humanRoleCount: 2,
      );
      expect(result, isNull);
    });
  });

  group('OrchestratorController.suggestionToShow — single human (participant)', () {
    test('lone human is prompted right after their own message', () {
      final output = outputWithBothRoles(eventA);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleA,
        currentUserId: userA,
        latestHumanMessageEventId: eventA,
        latestHumanMessageSenderId: userA, // the lone human spoke last
        humanRoleCount: 1,
      );
      expect(result, isNotNull);
      expect(result!.roleId, roleA);
    });

    test('not prompted when the latest message is not the current user\'s', () {
      final output = outputWithBothRoles(eventB);
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleA,
        currentUserId: userA,
        latestHumanMessageEventId: eventB,
        latestHumanMessageSenderId: userB,
        humanRoleCount: 1,
      );
      expect(result, isNull);
    });
  });

  group('OrchestratorController.suggestionToShow — guards', () {
    test('stale output (not based on latest human message) is dropped', () {
      final output = outputWithBothRoles(eventA); // computed from an older event
      final result = OrchestratorController.suggestionToShow(
        output: output,
        ownRoleId: roleB,
        currentUserId: userB,
        latestHumanMessageEventId: eventB, // a newer human message exists
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
        latestHumanMessageEventId: eventA,
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
        latestHumanMessageEventId: null,
        latestHumanMessageSenderId: null,
        humanRoleCount: 2,
      );
      expect(result, isNull);
    });
  });
}
