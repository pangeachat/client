import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';

/// The gate ChatView uses to pick the chat timeline vs the session start page.
/// The regression this locks (#7480): with a null plan (unhydrated, or the
/// activity removed from the backend) the old seat math read `0 - assigned
/// <= 0` and classified EVERY room as started — routing empty orphan rooms
/// into the chat timeline instead of the start page's removed-activity state.
void main() {
  group('activityStartedGate', () {
    test('finished sessions are always started', () {
      expect(
        activityStartedGate(
          finished: true,
          planRoleCount: null,
          assignedRoleCount: 0,
        ),
        isTrue,
      );
    });

    test('plan-less room with no assigned roles is NOT started — an empty '
        'orphan room shows the start page, not the chat timeline', () {
      expect(
        activityStartedGate(
          finished: false,
          planRoleCount: null,
          assignedRoleCount: 0,
        ),
        isFalse,
      );
    });

    test('plan-less room with assigned roles is started — real progress '
        'stays reviewable in the timeline even when the plan is gone', () {
      expect(
        activityStartedGate(
          finished: false,
          planRoleCount: null,
          assignedRoleCount: 1,
        ),
        isTrue,
      );
    });

    test('with a plan, started means every role is filled', () {
      expect(
        activityStartedGate(
          finished: false,
          planRoleCount: 2,
          assignedRoleCount: 1,
        ),
        isFalse,
      );
      expect(
        activityStartedGate(
          finished: false,
          planRoleCount: 2,
          assignedRoleCount: 2,
        ),
        isTrue,
      );
    });
  });
}
