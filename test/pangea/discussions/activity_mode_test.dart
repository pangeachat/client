import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_mode.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import '../activity_session_fixtures.dart';

/// Which activities are discussions (#9647, pangeachat/.github#700). A plan
/// is a discussion only when its mode is "discussion" in any case AND its
/// roles are exactly the one shared `participant` role. Every other plan,
/// older free-text modes included, plays as a roleplay.
void main() {
  const participant = [ActivityMode.discussionRoleId];

  group('ActivityMode.fromShape', () {
    test('a discussion-shaped plan is a discussion in any letter case', () {
      for (final mode in ['Discussion', 'discussion', 'DISCUSSION']) {
        expect(
          ActivityMode.fromShape(mode: mode, roleIds: participant),
          ActivityMode.discussion,
          reason: mode,
        );
      }
    });

    test('older modes play as roleplay', () {
      for (final mode in [
        'Roleplay',
        'Debate',
        'Decision Making',
        '20 Questions',
        'Conversation',
      ]) {
        expect(
          ActivityMode.fromShape(mode: mode, roleIds: participant),
          ActivityMode.roleplay,
          reason: mode,
        );
      }
    });

    test('no mode plays as roleplay', () {
      expect(
        ActivityMode.fromShape(mode: null, roleIds: participant),
        ActivityMode.roleplay,
      );
    });

    test('an old planner plan whose free-text mode is "Discussion" but whose '
        'roles are a roleplay\'s stays a roleplay', () {
      // choreo's v1 examples carry roleplay-shaped "Discussion" plans
      // ("Dog VS Cat").
      expect(
        ActivityMode.fromShape(mode: 'Discussion', roleIds: ['dog', 'cat']),
        ActivityMode.roleplay,
      );
      expect(
        ActivityMode.fromShape(
          mode: 'Discussion',
          roleIds: ['participant', 'moderator'],
        ),
        ActivityMode.roleplay,
      );
      expect(
        ActivityMode.fromShape(mode: 'Discussion', roleIds: ['speaker']),
        ActivityMode.roleplay,
      );
    });

    test('a card whose roles were not projected reads as roleplay', () {
      expect(
        ActivityMode.fromShape(mode: 'Discussion', roleIds: const []),
        ActivityMode.roleplay,
      );
    });
  });

  group('the plan and card readers agree', () {
    test('a discussion plan', () {
      expect(discussionActivityPlan().activityMode, ActivityMode.discussion);
      expect(twoRoleActivityPlan().activityMode, ActivityMode.roleplay);
    });

    QuestActivityCard card({String? mode, List<Object?>? roles}) =>
        QuestActivityCard.fromJson({
          'res': {
            'plan': {'activity_id': 'a1', 'mode': ?mode, 'roles': ?roles},
          },
        });

    test('a card projects its mode and role ids from the CMS row', () {
      expect(
        card(
          mode: 'Discussion',
          roles: [
            // A CMS role item carries its Payload row id as `id`; the role
            // id is `role_id`.
            {'id': '6650f0c2a1', 'role_id': 'participant', 'name': 'P'},
          ],
        ).activityMode,
        ActivityMode.discussion,
      );
      expect(
        card(
          mode: 'Discussion',
          roles: [
            {'id': '1', 'role_id': 'dog'},
            {'id': '2', 'role_id': 'cat'},
          ],
        ).activityMode,
        ActivityMode.roleplay,
      );
      expect(card(mode: 'Discussion').activityMode, ActivityMode.roleplay);
    });
  });

  group('what each mode offers', () {
    test('a discussion offers no suggestions; a roleplay does', () {
      expect(ActivityMode.discussion.offersSuggestions, isFalse);
      expect(ActivityMode.roleplay.offersSuggestions, isTrue);
    });

    test('a seat keyed by student is a discussion seat; one keyed by role '
        'is not', () {
      expect(
        ActivityMode.isDiscussionSeatKey(discussionSeatKey('@a:server')),
        isTrue,
      );
      expect(ActivityMode.isDiscussionSeatKey('participant'), isFalse);
      expect(ActivityMode.isDiscussionSeatKey('r1'), isFalse);
    });
  });
}
