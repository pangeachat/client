import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/world/world_map_client_extension.dart';

/// The new-learner gate behind the `multi_person_first_map` deprioritize
/// (world-map.instructions.md, "Priority matrix"). #7999 narrowed it: the term
/// used to clear as soon as the learner was *in* any session room, so a
/// playtester who started one activity and went back to panning the map was
/// immediately shown 3+ role pins, tried to start one, and hit a dead-end they
/// couldn't fill. It now clears only once they have FINISHED an activity.
void main() {
  group('countsAsFinishedActivitySession', () {
    test('a finished own role counts — the learner has done an activity', () {
      expect(
        countsAsFinishedActivitySession(
          activityId: 'a1',
          membership: Membership.join,
          ownRoleFinished: true,
          ownRoleArchived: false,
        ),
        isTrue,
      );
    });

    test('started but NOT finished does not count — the #7999 regression: '
        'exploring after starting one activity kept 3+ role pins sunk', () {
      expect(
        countsAsFinishedActivitySession(
          activityId: 'a1',
          membership: Membership.join,
          ownRoleFinished: false,
          ownRoleArchived: false,
        ),
        isFalse,
      );
    });

    test('an archived role counts even after "Continue" cleared finished_at — '
        'reopening a done activity must not re-sink every 3+ role pin', () {
      expect(
        countsAsFinishedActivitySession(
          activityId: 'a1',
          membership: Membership.join,
          ownRoleFinished: false,
          ownRoleArchived: true,
        ),
        isTrue,
      );
    });

    test('a non-activity room never counts', () {
      expect(
        countsAsFinishedActivitySession(
          activityId: null,
          membership: Membership.join,
          ownRoleFinished: true,
          ownRoleArchived: true,
        ),
        isFalse,
      );
    });

    test('an unaccepted invite is not a finished activity', () {
      for (final m in [Membership.invite, Membership.leave, Membership.ban]) {
        expect(
          countsAsFinishedActivitySession(
            activityId: 'a1',
            membership: m,
            ownRoleFinished: true,
            ownRoleArchived: true,
          ),
          isFalse,
          reason: 'membership $m should not count',
        );
      }
    });
  });
}
