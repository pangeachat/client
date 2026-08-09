import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';

/// The seat-occupancy invariant behind #7556: a role written in the
/// activity-role state event stays assigned unless its holder PROVABLY left
/// the room. The regression this locks: under lazy member loading the bot's
/// m.room.member event is often not loaded right after an invite refreshes
/// the member list, and the old participants-based filter counted that
/// unloaded holder as gone — the bot's seat evaporated ("Waiting to fill 1
/// roles") and the invitee could claim its role id, overwriting the bot's
/// entry in state.
void main() {
  ActivityRoleModel role(String id, String userId) =>
      ActivityRoleModel(id: id, userId: userId, role: id);

  group('roleHolderVacated', () {
    test('unloaded member event (null) keeps the seat occupied — the lazy '
        'member loading case that kicked the bot from its role', () {
      expect(roleHolderVacated(null), isFalse);
    });

    test('present memberships keep the seat occupied', () {
      expect(roleHolderVacated('join'), isFalse);
      expect(roleHolderVacated('invite'), isFalse);
      expect(roleHolderVacated('knock'), isFalse);
    });

    test('only positive evidence of leaving frees the seat', () {
      expect(roleHolderVacated('leave'), isTrue);
      expect(roleHolderVacated('ban'), isTrue);
    });
  });

  group('filterAssignedRoles', () {
    final roles = {
      'bot-role': role('bot-role', '@bot:server'),
      'human-role': role('human-role', '@human:server'),
    };

    test('a holder missing from loaded members stays assigned, so the seat '
        'count never shows "Waiting to fill" for an occupied seat', () {
      final assigned = filterAssignedRoles(
        roles,
        // bot's member event not loaded → null membership
        (id) => id == '@human:server' ? 'join' : null,
      );
      expect(assigned.keys, containsAll(['bot-role', 'human-role']));
    });

    test('a provably-left holder frees the seat', () {
      final assigned = filterAssignedRoles(
        roles,
        (id) => id == '@human:server' ? 'leave' : 'join',
      );
      expect(assigned.keys, ['bot-role']);
    });

    test('a banned holder frees the seat', () {
      final assigned = filterAssignedRoles(
        roles,
        (id) => id == '@human:server' ? 'ban' : 'join',
      );
      expect(assigned.keys, ['bot-role']);
    });
  });

  group('hasUnresolvedSeatEvidence', () {
    final roles = {
      'bot-role': role('bot-role', '@bot:server'),
      'human-role': role('human-role', '@human:server'),
    };

    test('no member events loaded — the initial-load state that left large '
        'cards deciding pending-vs-active without the facts (#8045)', () {
      expect(hasUnresolvedSeatEvidence(roles, (_) => null), isTrue);
    });

    test('one unloaded holder is enough to distrust the seat count', () {
      expect(
        hasUnresolvedSeatEvidence(
          roles,
          (id) => id == '@human:server' ? 'join' : null,
        ),
        isTrue,
      );
    });

    test('every holder resolved — nothing to refill', () {
      expect(
        hasUnresolvedSeatEvidence(
          roles,
          (id) => id == '@human:server' ? 'join' : 'leave',
        ),
        isFalse,
      );
    });

    test('a room with no activity-role state has no seats to resolve', () {
      expect(hasUnresolvedSeatEvidence(null, (_) => null), isFalse);
      expect(hasUnresolvedSeatEvidence({}, (_) => null), isFalse);
    });
  });

  group('guardSeatClaim', () {
    test('claiming a seat whose holder is absent from loaded members throws '
        '— the overwrite hole: updateRole keys by id, so an allowed claim '
        'would replace the bot\'s entry', () {
      expect(
        () => guardSeatClaim(
          claimantId: '@invitee:server',
          holder: role('bot-role', '@bot:server'),
          holderVacated: roleHolderVacated(null), // bot not loaded
          claimantHoldsSeat: false,
        ),
        throwsA(isA<RoleException>()),
      );
    });

    test('claiming a joined holder\'s seat throws', () {
      expect(
        () => guardSeatClaim(
          claimantId: '@invitee:server',
          holder: role('bot-role', '@bot:server'),
          holderVacated: roleHolderVacated('join'),
          claimantHoldsSeat: false,
        ),
        throwsA(isA<RoleException>()),
      );
    });

    test('claiming a provably-vacated seat is allowed (seat reuse after a '
        'leaver)', () {
      expect(
        () => guardSeatClaim(
          claimantId: '@invitee:server',
          holder: role('old-role', '@leaver:server'),
          holderVacated: roleHolderVacated('leave'),
          claimantHoldsSeat: false,
        ),
        returnsNormally,
      );
    });

    test('claiming an empty seat is allowed', () {
      expect(
        () => guardSeatClaim(
          claimantId: '@invitee:server',
          holder: null,
          holderVacated: false,
          claimantHoldsSeat: false,
        ),
        returnsNormally,
      );
    });

    test('a claimant who already holds a seat throws', () {
      expect(
        () => guardSeatClaim(
          claimantId: '@human:server',
          holder: null,
          holderVacated: false,
          claimantHoldsSeat: true,
        ),
        throwsA(isA<RoleException>()),
      );
    });

    test('re-claiming your own seat still counts as already having a role', () {
      expect(
        () => guardSeatClaim(
          claimantId: '@human:server',
          holder: role('my-role', '@human:server'),
          holderVacated: false,
          claimantHoldsSeat: true,
        ),
        throwsA(isA<RoleException>()),
      );
    });
  });
}
