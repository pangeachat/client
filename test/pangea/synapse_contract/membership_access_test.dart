@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show StreamedResponse;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/join_codes/request_room_code_extension.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/extensions/leave_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../endpoint_test_env.dart';
import 'contract_harness.dart';

/// Tier 2 — membership & access contract tests (client#8565).
///
/// Two personas: A owns rooms, B knocks/joins/gets banned. Every assertion
/// that matters reads the SERVER's state, not the local cache — leave paths
/// especially, since the SDK drops rooms locally even on a refused leave.
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
    // Per-file persona A (the four files run concurrently); fresh B each run
    // because Synapse's per-target rc_invites budget (burst 5, slow refill)
    // accrues across suite runs on a reused invitee.
    clientA = await ContractHarness.loggedIn('contract-membership-a');
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
    ContractHarness.trackRoom(clientA, roomId);
    final state = await ContractHarness.serverState(clientA, roomId);
    final code = state['m.room.join_rules']?['']?['access_code'] as String?;
    expect(
      code,
      isA<String>().having((c) => c.isNotEmpty, 'non-empty', true),
      reason: 'course must carry a non-empty access code',
    );
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

  group('request_room_code module endpoint', () {
    test('mints a non-empty access code', () async {
      final code = await clientA.requestSpaceCode();
      expect(code, isNotEmpty);
    });
  });

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
      expect(
        newCode,
        isA<String>().having((c) => c.isNotEmpty, 'non-empty', true),
      );
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

    test('a joined member comes back in already_joined', () async {
      final (roomId, code) = await makeCourse(suffix: 'rejoin');
      await clientB.knockWithCode(code);
      // Complete the join with the joinRoomById spelling the client uses.
      await clientB.joinRoomByIdWithAccessCheck(roomId);

      // Re-clicking your own class link: the flow branches on this list.
      final again = await clientB.knockWithCode(code);
      expect(again.alreadyJoined, contains(roomId));
      expect(again.roomIds, isNot(contains(roomId)));
    });

    test('an unknown code is a raw 400, not a silent empty 200', () async {
      Object? thrown;
      try {
        await clientB.knockWithCode('contract-no-such-code');
      } catch (e) {
        thrown = e;
      }
      expect(
        thrown,
        isA<StreamedResponse>().having((r) => r.statusCode, 'status', 400),
        reason:
            'the join flow treats a non-200 as "code not found"; pin the '
            'shape so a change breaks loudly',
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

  group('knock acceptance and denial', () {
    test('acceptKnock invites with the sentinel reason, and joinKnockedRoom '
        'completes and journals', () async {
      final (roomId, _) = await makeCourse(suffix: 'accept');
      // A REAL Matrix knock (the analytics-room / public-course flow) —
      // knock_with_code never produces knock state, so acceptKnock's whole
      // reason to exist is this path. The reason is smuggled metadata the
      // analytics-request reviewer UI filters on: assert the server
      // round-trips it into the member event.
      await clientB.knockAndRecordRoom(
        roomId,
        via: [serverName],
        reason: 'contract-knock-reason',
      );
      var state = await ContractHarness.serverState(clientA, roomId);
      expect(
        state['m.room.member']?[clientB.userID]?['reason'],
        'contract-knock-reason',
        reason: 'the knock reason must ride into m.room.member',
      );

      final room = clientA.getRoomById(roomId)!;
      await room.acceptKnock(clientB.userID!);

      state = await ContractHarness.serverState(clientA, roomId);
      final member = state['m.room.member']?[clientB.userID];
      expect(member?['membership'], 'invite');
      expect(
        member?['reason'],
        'invite_on_knock',
        reason:
            'the client keys knock-acceptance UI off this exact '
            'reason string',
      );

      // The knocker completes via joinKnockedRoom — the room.join()
      // spelling the chat-list auto-join sweep uses — which must also move
      // the room into accepted_invite_rooms in the knock journal.
      await ContractHarness.waitUntil(
        clientB,
        () => clientB.getRoomById(roomId)?.membership == Membership.invite,
      );
      final joinResp = await clientB.getRoomById(roomId)!.joinKnockedRoom();
      expect(
        joinResp,
        isNotNull,
        reason:
            'joinKnockedRoom swallows errors into null — a null here '
            'means the join or the journal write failed',
      );
      final after = await ContractHarness.serverState(clientA, roomId);
      expect(after['m.room.member']?[clientB.userID]?['membership'], 'join');

      final journal = await clientB.getAccountData(
        clientB.userID!,
        PangeaEventTypes.knockedRooms,
      );
      expect(
        (journal['accepted_invite_room_ids'] as List?)?.contains(roomId),
        true,
        reason: 'an accepted knock must move to accepted_invite_room_ids',
      );
    });

    test('deny-knock is a kick from knock state', () async {
      final (roomId, _) = await makeCourse(suffix: 'deny');
      // No via — the spelling public_course_preview uses.
      await clientB.knockAndRecordRoom(roomId);

      final room = clientA.getRoomById(roomId)!;
      await room.kick(clientB.userID!);

      final state = await ContractHarness.serverState(clientA, roomId);
      final member = state['m.room.member']?[clientB.userID];
      expect(
        member?['membership'],
        'leave',
        reason: 'denying a join request must clear the knock',
      );
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

  group('join by alias', () {
    test('joinRoomWithAccessCheck resolves an alias with via', () async {
      // The public-course-preview spelling: alias target + server hint —
      // a different endpoint (/join/{alias}?via=) from joinRoomById.
      final alias = 'contract-alias-${DateTime.now().millisecondsSinceEpoch}';
      final roomId = await clientA.createRoom(
        visibility: Visibility.public,
        preset: CreateRoomPreset.publicChat,
        roomAliasName: alias,
        name: 'Contract alias room',
      );
      ContractHarness.trackRoom(clientA, roomId);

      final joinResp = await clientB.joinRoomWithAccessCheck(
        '#$alias:$serverName',
        serverName: [serverName],
      );
      expect(joinResp.roomId, roomId, reason: 'alias must resolve');
      final state = await ContractHarness.serverState(clientA, roomId);
      expect(state['m.room.member']?[clientB.userID]?['membership'], 'join');
    });
  });

  group('leave semantics', () {
    test('leaveIgnoringUnknownRoom tolerates a room Synapse forgot', () async {
      final ghost = Room(id: '!contract-ghost:$serverName', client: clientB);
      // Must complete without throwing — the M_NOT_FOUND/M_UNKNOWN tolerance
      // the client relies on for purged activity sessions. (No assertion
      // beyond "no throw": the tolerated errcode set IS the contract.)
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
      // Precondition: the cascade must have a child to leave, or the test
      // passes vacuously.
      expect(space.spaceChildren.any((c) => c.roomId == chatId), true);

      await space.leaveSpace();

      // SERVER truth, not the local cache: leaveSpace swallows failures and
      // the SDK drops rooms locally even when the server refuses the leave —
      // a local-cache assertion here is green by construction.
      final spaceState = await ContractHarness.serverState(clientA, spaceId);
      expect(
        spaceState['m.room.member']?[clientA.userID]?['membership'],
        'leave',
        reason: 'the space itself must be left server-side',
      );
      final chatState = await ContractHarness.serverState(clientA, chatId);
      expect(
        chatState['m.room.member']?[clientA.userID]?['membership'],
        'leave',
        reason: 'leaveSpace must cascade to the child chat server-side',
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
      ContractHarness.trackRoom(clientA, chatId);
      await ContractHarness.waitUntil(
        clientA,
        () => clientA.getRoomById(chatId) != null,
      );

      // A live space child means a NON-EMPTY via list; a detached child is
      // the same event with empty content. isNotNull cannot tell them apart.
      List? via(Map<String, Map<String, Map<String, Object?>>> s) =>
          s['m.space.child']?[chatId]?['via'] as List?;

      // addToSpace: documented as detach-first single-parent.
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
      // KNOWN GAP, pinned deliberately: addToSpace's detach loop reads
      // `pangeaSpaceParents` on the DESTINATION space, not on the child, so
      // the old parent keeps a LIVE child link. When the bug is fixed this
      // via list becomes empty — flip the matcher to isEmpty/isNull then
      // (follow-up task from client#8565).
      expect(
        via(s1),
        isNotEmpty,
        reason:
            'documents the latent single-parent bug — if this fails, the '
            'detach was fixed: flip this assertion',
      );
      expect(via(s2), isNotEmpty);

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
      expect(via(s1), isNotEmpty);
      expect(
        via(s2),
        isNotEmpty,
        reason: 'KeepingParents must not detach the other space',
      );
    });
  });
}
