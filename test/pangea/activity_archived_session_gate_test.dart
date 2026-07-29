import 'package:flutter_test/flutter_test.dart';

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
}
