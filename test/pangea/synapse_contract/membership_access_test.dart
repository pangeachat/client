@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/extensions/leave_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../endpoint_test_env.dart';
import 'contract_harness.dart';

/// Tier 2 — membership & access contract tests (client#8565).
///
/// Two personas: learner A owns rooms, learner B knocks/joins/gets banned.
/// Every assertion that matters reads the SERVER's state, not the local cache.
void main() {
  if (!EndpointTestEnv.available) {
    test(
      'synapse contract suite is local-only',
      () {},
      skip: 'requires client/.env',
    );
    return;
  }

  late Client clientA;
  late Client clientB;
  late String serverName;

  setUpAll(() async {
    await ContractHarness.initTestEnvironment();
    clientA = await ContractHarness.loggedIn(ContractHarness.learnerA);
    // Fresh B each run: Synapse's rc_invites per-target budget (burst 5,
    // ~1 refill / 5 min) accrues across suite runs on a reused persona.
    clientB = await ContractHarness.loggedIn(
      'contract-b-${DateTime.now().millisecondsSinceEpoch}',
    );
    serverName = clientA.userID!.split(':').last;
  });

  tearDownAll(() async {
    await ContractHarness.dispose(clientA);
    await ContractHarness.dispose(clientB);
  });

  /// A knockable course space owned by A; returns (roomId, accessCode) with
  /// the code read back from the server, exactly as share links would use it.
  Future<(String, String)> makeCourse({String suffix = ''}) async {
    final roomId = await clientA.createPangeaSpace(
      name:
          'Contract Access $suffix '
          '${DateTime.now().millisecondsSinceEpoch}',
      visibility: Visibility.private,
      joinRules: JoinRules.knock,
    );
    final state = await ContractHarness.serverState(clientA, roomId);
    final code = state['m.room.join_rules']?['']?['access_code'] as String?;
    expect(code, isNotNull, reason: 'course must carry an access code');
    // Room extensions read LOCAL state; wait for it to catch up with the
    // server before handing the room to a test.
    await ContractHarness.waitUntil(
      clientA,
      () =>
          clientA.getRoomById(roomId)?.getState(EventTypes.RoomJoinRules) !=
          null,
    );
    return (roomId, code!);
  }

  group('join-rules rewrites', () {
    test('setCustomJoinRules preserves the access_code', () async {
      final (roomId, code) = await makeCourse(suffix: 'rules');
      final room = clientA.getRoomById(roomId);
      expect(room, isNotNull);

      await room!.setCustomJoinRules(JoinRules.public);

      final state = await ContractHarness.serverState(clientA, roomId);
      final joinRules = state['m.room.join_rules']?[''];
      expect(joinRules?['join_rule'], 'public');
      expect(
        joinRules?['access_code'],
        code,
        reason: 'a join-rule change must not lose the course code',
      );
    });

    test('generateAndSetJoinCode mints and stores a fresh code', () async {
      final (roomId, oldCode) = await makeCourse(suffix: 'recode');
      final room = clientA.getRoomById(roomId)!;

      await room.generateAndSetJoinCode();

      final state = await ContractHarness.serverState(clientA, roomId);
      final newCode = state['m.room.join_rules']?['']?['access_code'];
      expect(newCode, isA<String>());
      expect(newCode, isNot(oldCode));
    });
  });

  group('knock_with_code module endpoint', () {
    test('a valid code yields a server-side invite', () async {
      final (roomId, code) = await makeCourse(suffix: 'knock');

      final resp = await clientB.knockWithCode(code);
      expect(resp.roomIds, contains(roomId));

      // NOT a Matrix knock, despite the name: the module validates the code
      // and issues an invite directly — the caller never enters knock state
      // (knock-with-code.instructions.md).
      final state = await ContractHarness.serverState(clientA, roomId);
      expect(
        state['m.room.member']?[clientB.userID]?['membership'],
        'invite',
        reason: 'the code IS the authorization: the module invites directly',
      );
    });

    test('a user banned from every matched room gets the typed 403', () async {
      final (roomId, code) = await makeCourse(suffix: 'ban');
      final room = clientA.getRoomById(roomId)!;
      await room.ban(clientB.userID!);

      await expectLater(
        clientB.knockWithCode(code),
        throwsA(isA<BannedFromRoomException>()),
        reason:
            'the ORG.PANGEA.BANNED_FROM_ROOM 403 contract the join flow '
            'branches on (#7592)',
      );
    });
  });

  group('knock acceptance', () {
    test('acceptKnock invites with the sentinel reason, and the knocker '
        'joins by id', () async {
      final (roomId, _) = await makeCourse(suffix: 'accept');
      // A REAL Matrix knock (the analytics-room / public-course flow) —
      // knock_with_code never produces knock state, so acceptKnock's whole
      // reason to exist is this path.
      await clientB.knockAndRecordRoom(roomId, via: [serverName]);

      final room = clientA.getRoomById(roomId)!;
      await room.acceptKnock(clientB.userID!);

      final state = await ContractHarness.serverState(clientA, roomId);
      final member = state['m.room.member']?[clientB.userID];
      expect(member?['membership'], 'invite');
      expect(
        member?['reason'],
        'invite_on_knock',
        reason:
            'the client keys knock-acceptance UI off this exact '
            'reason string',
      );

      // The knocker completes the flow with the joinRoomById spelling
      // (join_room_analytics_access_extension).
      final joinResp = await clientB.joinRoomByIdWithAccessCheck(roomId);
      expect(joinResp.roomId, roomId);
      final after = await ContractHarness.serverState(clientA, roomId);
      expect(after['m.room.member']?[clientB.userID]?['membership'], 'join');
    });
  });

  group('knockAndRecordRoom', () {
    test('knocks server-side and journals into account data', () async {
      final (roomId, _) = await makeCourse(suffix: 'record');

      await clientB.knockAndRecordRoom(roomId, via: [serverName]);

      final state = await ContractHarness.serverState(clientA, roomId);
      expect(state['m.room.member']?[clientB.userID]?['membership'], 'knock');

      // The journal is the org.pangea.knocked_rooms account-data type,
      // asserted server-side.
      final journal = await clientB.getAccountData(
        clientB.userID!,
        PangeaEventTypes.knockedRooms,
      );
      expect(
        (journal['room_ids'] as List?)?.contains(roomId),
        true,
        reason: 'knock journal must record the room',
      );
    });
  });

  group('leave semantics', () {
    test('leaveIgnoringUnknownRoom tolerates a room Synapse forgot', () async {
      final ghost = Room(id: '!contract-ghost:$serverName', client: clientB);
      // Must complete without throwing — the M_NOT_FOUND/M_UNKNOWN tolerance
      // the client relies on for purged activity sessions.
      await ghost.leaveIgnoringUnknownRoom();
    });

    test('leaveSpace cascades to visible children', () async {
      final (spaceId, _) = await makeCourse(suffix: 'cascade');
      final chatId = await clientA.createPangeaGroupChat(
        'Contract cascade chat',
        initialState: [
          await clientA.generateCustomJoinRules(
            JoinRules.knockRestricted,
            allowRoomId: spaceId,
          ),
        ],
      );
      final space = clientA.getRoomById(spaceId)!;
      await space.addToSpace(chatId);
      await ContractHarness.waitUntil(
        clientA,
        () => space.spaceChildren.any((c) => c.roomId == chatId),
      );

      await space.leaveSpace();
      await clientA.oneShotSync();

      expect(
        clientA.getRoomById(spaceId)?.membership,
        isNot(Membership.join),
        reason: 'the space itself must be left',
      );
      expect(
        clientA.getRoomById(chatId)?.membership,
        isNot(Membership.join),
        reason: 'leaveSpace must cascade to the child chat',
      );
    });
  });

  group('space hierarchy', () {
    test('space-child attach mechanics (single-parent detach is a known '
        'gap)', () async {
      final (space1, _) = await makeCourse(suffix: 'parent1');
      final (space2, _) = await makeCourse(suffix: 'parent2');
      final chatId = await clientA.createPangeaGroupChat(
        'Contract hierarchy chat',
        initialState: [
          await clientA.generateCustomJoinRules(
            JoinRules.knockRestricted,
            allowRoomId: space1,
          ),
        ],
      );
      await ContractHarness.waitUntil(
        clientA,
        () => clientA.getRoomById(chatId) != null,
      );

      // addToSpace: detach-first, exactly one parent.
      await clientA.getRoomById(space1)!.addToSpace(chatId);
      await ContractHarness.waitUntil(
        clientA,
        () => clientA
            .getRoomById(space1)!
            .spaceChildren
            .any((c) => c.roomId == chatId),
      );
      await clientA.getRoomById(space2)!.addToSpace(chatId);

      var s1 = await ContractHarness.serverState(clientA, space1);
      var s2 = await ContractHarness.serverState(clientA, space2);
      // KNOWN GAP, pinned deliberately: addToSpace is documented to detach
      // the child from its previous spaces (single-parent invariant), but its
      // detach loop reads `pangeaSpaceParents` on the DESTINATION space, not
      // on the child — so the old parent keeps its m.space.child event. This
      // asserts the ACTUAL wire behavior; flip it to assert the detach when
      // the bug is fixed (tracked as a follow-up from client#8565).
      expect(
        s1['m.space.child']?[chatId],
        isNotNull,
        reason:
            'documents the latent single-parent bug — if this fails, the '
            'detach was fixed: flip this assertion',
      );
      expect(s2['m.space.child']?[chatId], isNotNull);

      // addSpaceChildKeepingParents: shared into both (activity sessions).
      await ContractHarness.waitUntil(
        clientA,
        () => clientA
            .getRoomById(space2)!
            .spaceChildren
            .any((c) => c.roomId == chatId),
      );
      await clientA.getRoomById(space1)!.addSpaceChildKeepingParents(chatId);
      s1 = await ContractHarness.serverState(clientA, space1);
      s2 = await ContractHarness.serverState(clientA, space2);
      expect(s1['m.space.child']?[chatId], isNotNull);
      expect(
        s2['m.space.child']?[chatId],
        isNotNull,
        reason: 'KeepingParents must not detach the other space',
      );
    });
  });
}
