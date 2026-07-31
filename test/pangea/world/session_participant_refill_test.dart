import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/world_map_pins_manager.dart';

/// #8045: the map decides a large card's seat row and its ongoing
/// pending-vs-active split from `Room.getParticipants()`, but `m.room.member`
/// events never ride the SDK's preloaded-state path — so at startup that list
/// is empty for every session room the learner hasn't opened, and the seats
/// fall back to "unknown membership = still occupied" instead of evidence.
/// [needsParticipantRefill] picks the rooms worth a member refill.
void main() {
  group('needsParticipantRefill — a room never filled', () {
    test('unresolved seats earn a refill: the startup state behind the '
        'avatar-less, wrongly-seated large cards', () {
      expect(
        needsParticipantRefill(
          everFilled: false,
          filledAtJoinedCount: null,
          joinedCount: 2,
          hasUnresolvedSeats: true,
        ),
        isTrue,
      );
    });

    test('seats already resting on real membership are left alone', () {
      expect(
        needsParticipantRefill(
          everFilled: false,
          filledAtJoinedCount: null,
          joinedCount: 2,
          hasUnresolvedSeats: false,
        ),
        isFalse,
      );
    });
  });

  group('needsParticipantRefill — a room already filled', () {
    test('an unchanged joined count never re-qualifies, so an inconsistently '
        'reported room cannot put the sweep in a loop', () {
      expect(
        needsParticipantRefill(
          everFilled: true,
          filledAtJoinedCount: 2,
          joinedCount: 2,
          // Would have earned a refill had it never been filled.
          hasUnresolvedSeats: true,
        ),
        isFalse,
      );
    });

    test('a moved joined count re-qualifies it — someone joined or left since '
        'the fill, and sync skips member events for these partial rooms', () {
      expect(
        needsParticipantRefill(
          everFilled: true,
          filledAtJoinedCount: 2,
          joinedCount: 1,
          hasUnresolvedSeats: false,
        ),
        isTrue,
      );
    });

    test(
      'a count that only becomes known after the fill re-qualifies once',
      () {
        expect(
          needsParticipantRefill(
            everFilled: true,
            filledAtJoinedCount: null,
            joinedCount: 3,
            hasUnresolvedSeats: false,
          ),
          isTrue,
        );
      },
    );

    test('a count that stays unknown never re-qualifies', () {
      expect(
        needsParticipantRefill(
          everFilled: true,
          filledAtJoinedCount: null,
          joinedCount: null,
          hasUnresolvedSeats: true,
        ),
        isFalse,
      );
    });
  });
}
