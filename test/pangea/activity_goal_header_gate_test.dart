import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';

/// The gate deciding whether the floating goal header is on screen — and so
/// whether the goal tutorial has anything to point at.
///
/// The regression this locks (#8184): the gate omitted the start-page clause,
/// and every OTHER condition here is already true on an activity's waiting
/// room. So the tutorial launched at a target that was not mounted, the overlay
/// found nothing to light and tore itself down, and the sequence was left
/// active — which then blocked every later attempt for the rest of the session.
void main() {
  group('activityGoalHeaderGate', () {
    bool gate({
      bool showsStartPage = false,
      bool showsActivityChatUI = true,
      bool hasSummary = false,
      bool hasPickedRole = true,
      bool hasGoals = true,
    }) => activityGoalHeaderGate(
      showsStartPage: showsStartPage,
      showsActivityChatUI: showsActivityChatUI,
      hasSummary: hasSummary,
      hasPickedRole: hasPickedRole,
      hasGoals: hasGoals,
    );

    test('a running activity with a role and goals has the header', () {
      expect(gate(), isTrue);
    });

    test('the waiting room does NOT have the header, even with a role and '
        'goals — the start page replaces the whole timeline', () {
      expect(gate(showsStartPage: true), isFalse);
    });

    test('a room not showing activity chat UI has no header', () {
      expect(gate(showsActivityChatUI: false), isFalse);
    });

    test('a summarised activity has no header — the run is over', () {
      expect(gate(hasSummary: true), isFalse);
    });

    test('no picked role means no header to point at', () {
      expect(gate(hasPickedRole: false), isFalse);
    });

    test('a role with no goals has nothing for the header to show', () {
      expect(gate(hasGoals: false), isFalse);
    });
  });
}
