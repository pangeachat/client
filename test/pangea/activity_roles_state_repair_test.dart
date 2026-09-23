import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/activity_sessions/activity_auto_save_service.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_state_repair.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'get_test_client.dart';

/// #9229 — a sync that replays an older copy of the shared role event in its
/// `state` block (a forked room history) reverted a finished role to
/// unfinished, and the chat fell back to "Waiting to fill 1 role". The repair
/// re-reads the server's current role event and re-applies it.
void main() {
  sqfliteFfiInit();

  late Client client;
  late ActivityRolesStateRepair repair;
  late Completer<MatrixEvent> serverRead;
  var serverReads = 0;
  // Distinct room ids per test: sqflite's ':memory:' database is shared
  // process-wide, so rooms outlive a client.
  var roomCounter = 0;
  late String roomId;

  MatrixEvent rolesEvent(String eventId, {String? finishedAt, int ts = 0}) =>
      MatrixEvent(
        type: PangeaEventTypes.activityRole,
        stateKey: '',
        senderId: '@test:fakeServer.notExisting',
        eventId: eventId,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
        content: {
          'roles': {
            'b': {
              'id': 'b',
              'user_id': '@test:fakeServer.notExisting',
              'role': 'B',
              'finished_at': finishedAt,
              'archived_at': null,
            },
          },
        },
      );

  final finished = '2026-09-23T13:55:30.569Z';

  Future<void> serverSync(
    String nextBatch, {
    List<MatrixEvent>? state,
    List<MatrixEvent>? timeline,
  }) => client.handleSync(
    SyncUpdate(
      nextBatch: nextBatch,
      rooms: RoomsUpdate(
        join: {
          roomId: JoinedRoomUpdate(
            state: state,
            timeline: timeline == null
                ? null
                : TimelineUpdate(events: timeline, limited: false),
          ),
        },
      ),
    ),
  );

  String? heldId() =>
      (client.getRoomById(roomId)!.getState(PangeaEventTypes.activityRole)
              as Event)
          .eventId;

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    client = await getTestClient();
    // The app preloads the role event (client_manager.dart); without it a
    // partial room never holds the event in memory.
    client.importantStateEvents.add(PangeaEventTypes.activityRole);
    roomId = '!session${roomCounter++}:fakeServer.notExisting';
    serverReads = 0;
    serverRead = Completer();
    repair = ActivityRolesStateRepair(
      client: client,
      fetchCurrentRoles: (_) {
        serverReads++;
        return serverRead.future;
      },
    );
    // The room exists, with the learner's finished role, before the repair
    // starts watching.
    await serverSync(
      'b0',
      timeline: [rolesEvent(r'$new', finishedAt: finished)],
    );
    repair.start();
  });

  tearDown(() async {
    repair.dispose();
    await client.dispose();
  });

  test('an older role event replayed in a state block is repaired back to '
      'the server event', () async {
    await serverSync('b1', state: [rolesEvent(r'$old')]);
    expect(heldId(), r'$old', reason: 'the SDK applied the replayed copy');
    expect(client.getRoomById(roomId)!.hasCompletedRole, isFalse);

    serverRead.complete(rolesEvent(r'$new', finishedAt: finished));
    await settle();

    expect(serverReads, 1);
    expect(heldId(), r'$new');
    expect(client.getRoomById(roomId)!.hasCompletedRole, isTrue);
  });

  test('a state block that matches the server changes nothing', () async {
    await serverSync('b1', state: [rolesEvent(r'$new', finishedAt: finished)]);
    serverRead.complete(rolesEvent(r'$new', finishedAt: finished));
    await settle();

    expect(serverReads, 1);
    expect(heldId(), r'$new');
  });

  test('role events delivered in the timeline are not checked', () async {
    await serverSync('b1', timeline: [rolesEvent(r'$newer', ts: 1)]);
    await settle();

    expect(serverReads, 0);
  });

  test(
    'client-built syncs (history pages, local echoes) are not checked',
    () async {
      await serverSync('', state: [rolesEvent(r'$old')]);
      await settle();

      expect(serverReads, 0);
    },
  );

  test('a newer role event that lands during the server read wins', () async {
    await serverSync('b1', state: [rolesEvent(r'$old')]);
    await serverSync('b2', timeline: [rolesEvent(r'$newest', ts: 2)]);

    serverRead.complete(rolesEvent(r'$new', finishedAt: finished));
    await settle();

    expect(heldId(), r'$newest');
  });

  group('archiveEchoPending', () {
    test('holding the event the archive was built from waits for the echo', () {
      expect(
        archiveEchoPending(archivedFromEventId: r'$a', heldEventId: r'$a'),
        isTrue,
      );
    });

    test('a different held event (a co-player overwrite) repairs', () {
      expect(
        archiveEchoPending(archivedFromEventId: r'$a', heldEventId: r'$b'),
        isFalse,
      );
    });

    test('no archive this run never waits', () {
      expect(
        archiveEchoPending(archivedFromEventId: null, heldEventId: r'$a'),
        isFalse,
      );
    });
  });
}
