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

  late Client client;

  setUpAll(() async {
    client = await getTestClient();
    // Lets the fake API answer the room-scoped account_data PUT that clearing
    // the unread flag performs.
    FakeMatrixApi.client = client;
  });

  setUp(() => FakeMatrixApi.calledEndpoints.clear());

  Room room({
    int notificationCount = 0,
    bool markedUnread = false,
    Event? lastEvent,
  }) => Room(
    id: '!1234:example.com',
    client: client,
    notificationCount: notificationCount,
    lastEvent: lastEvent,
    roomAccountData: markedUnread
        ? {
            'm.marked_unread': BasicEvent(
              type: 'm.marked_unread',
              content: {'unread': true},
            ),
          }
        : {},
  );

  group('showsUnreadIndicator', () {
    test('is true for a room with an unread notification count', () {
      // The #8009 case: unread count, no explicit flag. Keying off
      // markedUnread here is what produced the wrong "Mark as unread" label.
      final r = room(notificationCount: 3);

      expect(r.markedUnread, isFalse);
      expect(r.showsUnreadIndicator, isTrue);
    });

    test('is true for a room flagged unread with no notification count', () {
      final r = room(markedUnread: true);

      expect(r.notificationCount, 0);
      expect(r.showsUnreadIndicator, isTrue);
    });

    test('is true when both the count and the flag are set', () {
      expect(
        room(notificationCount: 1, markedUnread: true).showsUnreadIndicator,
        isTrue,
      );
    });

    test('is false for a room with no count, no flag and no new messages', () {
      final r = room();

      expect(r.hasNewMessages, isFalse);
      expect(r.showsUnreadIndicator, isFalse);
    });
  });

  group('clearUnread', () {
    Event message({required String eventId, String? senderId}) => Event(
      eventId: eventId,
      type: EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': 'hi'},
      senderId: senderId ?? '@other:example.com',
      originServerTs: DateTime.now(),
      room: Room(id: '!1234:example.com', client: client),
    );

    bool calledMatching(String fragment) =>
        FakeMatrixApi.calledEndpoints.keys.any((e) => e.contains(fragment));

    test('sends a read receipt for the latest event', () async {
      // markUnread() alone never sets a read marker, which is why the badge
      // count survived a mark-unread/mark-read round trip before the fix. The
      // receipt is what actually zeroes notificationCount on the server.
      final r = room(
        notificationCount: 2,
        lastEvent: message(eventId: '\$1234:example.com'),
      );

      await r.clearUnread();

      expect(calledMatching('read_markers'), isTrue);
    });

    test('also clears the explicit unread flag when it is set', () async {
      final r = room(
        markedUnread: true,
        lastEvent: message(eventId: '\$1234:example.com'),
      );

      await r.clearUnread();

      expect(calledMatching('read_markers'), isTrue);
      expect(calledMatching('m.marked_unread'), isTrue);
    });

    test('does not touch the unread flag when it was never set', () async {
      final r = room(
        notificationCount: 1,
        lastEvent: message(eventId: '\$1234:example.com'),
      );

      await r.clearUnread();

      expect(calledMatching('m.marked_unread'), isFalse);
    });

    test(
      'skips the receipt when the last event is a pending local echo',
      () async {
        // A pending event carries a transaction id, not a valid event id, so
        // sending a receipt for it would fail server-side.
        final r = room(
          notificationCount: 1,
          lastEvent: message(
            eventId: 'web1700000000000',
            senderId: client.userID!,
          ),
        );

        await r.clearUnread();

        expect(calledMatching('read_markers'), isFalse);
      },
    );

    test('is a no-op on a room with nothing to clear', () async {
      await room().clearUnread();

      expect(FakeMatrixApi.calledEndpoints, isEmpty);
    });
  });
}
