import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/chat_details/chat_context_menu_action.dart';
import 'get_test_client.dart';

/// Regression coverage for #8009 — the chat-list "more options" menu offered
/// "Mark as unread" on a chat that already had an unread count, and its read
/// branch left the count untouched.
///
/// The bug was that both the label and the action keyed off `markedUnread` (the
/// explicit `m.marked_unread` flag) rather than whether the room actually reads
/// as unread.
void main() {
  sqfliteFfiInit();

  // read_markers is only stubbed for a handful of room ids in FakeMatrixApi.
  const roomId = '!1234:example.com';

  late Client client;
  late String confirmedEventId;
  late String pendingTxId;

  // sqflite's ':memory:' database is shared process-wide, so room and event
  // rows outlive a client. Fresh event ids per test keep handleSync from
  // deduping against an earlier test's copy and keeping its sender.
  var testCounter = 0;

  setUp(() async {
    client = await getTestClient();
    FakeMatrixApi.client = client;
    testCounter++;
    confirmedEventId = '\$confirmed$testCounter:example.com';
    pendingTxId = 'web170000000000$testCounter';
  });

  /// Builds the room through a sync so it has a real timeline, which is what
  /// receipt targeting reads from.
  Future<Room> syncRoom({
    int notificationCount = 0,
    bool markedUnread = false,
    bool lastMessageFromSelf = false,
  }) async {
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'batch1',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              unreadNotifications: UnreadNotificationCounts(
                notificationCount: notificationCount,
                highlightCount: 0,
              ),
              // Always sent, so a leaked flag from an earlier test can't
              // linger as an implicit true.
              accountData: [
                BasicEvent(
                  type: 'm.marked_unread',
                  content: {'unread': markedUnread},
                ),
              ],
              timeline: TimelineUpdate(
                prevBatch: 'prev1',
                events: [
                  MatrixEvent(
                    eventId: confirmedEventId,
                    type: EventTypes.Message,
                    content: {'msgtype': 'm.text', 'body': 'a message'},
                    senderId: lastMessageFromSelf
                        ? client.userID!
                        : '@other:example.com',
                    originServerTs: DateTime.now(),
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );
    return client.getRoomById(roomId)!;
  }

  /// Stacks an unsent local echo on top, mirroring the fake sync the SDK emits
  /// from `sendEvent`. Its id is a transaction id, not an event id.
  Future<Room> addPendingEcho() async {
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'batch2',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              timeline: TimelineUpdate(
                events: [
                  MatrixEvent(
                    eventId: pendingTxId,
                    type: EventTypes.Message,
                    content: {'msgtype': 'm.text', 'body': 'my pending reply'},
                    senderId: client.userID!,
                    originServerTs: DateTime.now(),
                    unsigned: {
                      messageSendingStatusKey: EventStatus.sending.intValue,
                      'transaction_id': pendingTxId,
                    },
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );
    return client.getRoomById(roomId)!;
  }

  Iterable<String> callsMatching(String fragment) => FakeMatrixApi
      .calledEndpoints
      .entries
      .where((e) => e.key.contains(fragment))
      .expand((e) => e.value)
      .map((body) => body.toString());

  group('showsUnreadIndicator', () {
    test('is true for a room with an unread notification count', () async {
      // The #8009 case: unread count, no explicit flag. Keying off
      // markedUnread here is what produced the wrong "Mark as unread" label.
      final room = await syncRoom(notificationCount: 3);

      expect(room.markedUnread, isFalse);
      expect(room.showsUnreadIndicator, isTrue);
    });

    test('is true for a room flagged unread with no count', () async {
      final room = await syncRoom(markedUnread: true);

      expect(room.notificationCount, 0);
      expect(room.showsUnreadIndicator, isTrue);
    });

    test('is true when both the count and the flag are set', () async {
      final room = await syncRoom(notificationCount: 1, markedUnread: true);

      expect(room.showsUnreadIndicator, isTrue);
    });

    test('is false for a read chat whose newest message is your own', () async {
      final room = await syncRoom(lastMessageFromSelf: true);

      expect(room.hasNewMessages, isFalse);
      expect(room.showsUnreadIndicator, isFalse);
    });
  });

  group('clearUnread', () {
    test('sends a read receipt for the latest event', () async {
      // markUnread() alone never sets a read marker, which is why the badge
      // count survived a mark-unread/mark-read round trip before the fix. The
      // receipt is what actually zeroes notificationCount on the server.
      final room = await syncRoom(notificationCount: 2);
      FakeMatrixApi.calledEndpoints.clear();

      await room.clearUnread();

      expect(callsMatching('read_markers').single, contains(confirmedEventId));
    });

    test('also clears the explicit unread flag when it is set', () async {
      final room = await syncRoom(notificationCount: 1, markedUnread: true);
      FakeMatrixApi.calledEndpoints.clear();

      await room.clearUnread();

      expect(callsMatching('read_markers'), isNotEmpty);
      expect(callsMatching('m.marked_unread'), isNotEmpty);
    });

    test('does not touch the unread flag when it was never set', () async {
      final room = await syncRoom(notificationCount: 1);
      FakeMatrixApi.calledEndpoints.clear();

      await room.clearUnread();

      expect(callsMatching('m.marked_unread'), isEmpty);
    });

    test('still marks read when an unsent echo is the newest event', () async {
      // Reachable by replying from a notification, or when a send is queued
      // offline. The echo's id is a transaction id, so a receipt aimed at it
      // would be rejected — but the confirmed messages beneath it must still
      // be marked read rather than the whole action silently no-opping.
      await syncRoom(notificationCount: 2);
      final room = await addPendingEcho();
      expect(room.lastEvent?.eventId, pendingTxId);
      expect(room.lastEvent!.eventId.isValidMatrixId, isFalse);
      FakeMatrixApi.calledEndpoints.clear();

      await room.clearUnread();

      final receipt = callsMatching('read_markers').single;
      expect(receipt, contains(confirmedEventId));
      expect(receipt, isNot(contains(pendingTxId)));
    });
  });
}
