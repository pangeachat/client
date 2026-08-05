import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';

/// The gate deciding whether a confirmed-removed activity renders the
/// read-only archived view and its "no longer supported" notice.
///
/// The removed-activity ladder is scoped to session ROOMS — every rung renders
/// what the room itself holds (roles, stars, timeline) so past work stays
/// reviewable (activities.instructions.md, "Removed or unresolvable
/// activities"). The regression this locks (#7918): the gate was `removed`
/// alone, so a removed activity opened from a bare world-map pin — no session,
/// nothing to review — rendered an all-but-empty archived page telling the
/// learner their activity "ran on an older version". Without a session that
/// notice is simply wrong, and the map dead-ends.
void main() {
  group('archivedSessionGate', () {
    test('removed activity WITH a session is archived — the session is the '
        'thing being reviewed', () {
      expect(
        archivedSessionGate(activityRemoved: true, hasSessionRoom: true),
        isTrue,
      );
    });

    test('removed activity with NO session is not archived — a bare map pin '
        'has nothing to review', () {
      expect(
        archivedSessionGate(activityRemoved: true, hasSessionRoom: false),
        isFalse,
      );
    });

    test('a healthy activity is never archived, session or not', () {
      expect(
        archivedSessionGate(activityRemoved: false, hasSessionRoom: true),
        isFalse,
      );
      expect(
        archivedSessionGate(activityRemoved: false, hasSessionRoom: false),
        isFalse,
      );
    });
  });

  /// The gate deciding whether the archived view offers a Leave button.
  ///
  /// A removed activity's session can never be continued or finished and no
  /// one else can be invited into it, so before #8064 a joined learner had no
  /// exit at all: the session sat in their chat list forever. Leaving is the
  /// one action still available on this dead room — but only to someone
  /// actually in it.
  group('archivedLeaveGate', () {
    test('a joined learner on an archived session can leave', () {
      expect(
        archivedLeaveGate(isArchived: true, membership: Membership.join),
        isTrue,
      );
    });

    test('a live activity never offers leave here — its session is still '
        'playable and the ⋮ menu owns that action', () {
      expect(
        archivedLeaveGate(isArchived: false, membership: Membership.join),
        isFalse,
      );
    });

    test('nothing to leave without a joined membership', () {
      for (final membership in [
        Membership.invite,
        Membership.leave,
        Membership.ban,
        null,
      ]) {
        expect(
          archivedLeaveGate(isArchived: true, membership: membership),
          isFalse,
          reason: 'membership $membership should not offer leave',
        );
      }
    });
  });
}
