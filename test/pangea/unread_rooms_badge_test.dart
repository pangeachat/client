import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/unread_rooms_client_extension.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import 'get_test_client.dart';

/// #9236 — the rooms a badge counts are scanned once per rebuild
/// ([UnreadRoomsClientExtension.unreadRooms]) and handed to each badge, which
/// only displays them.
void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room addRoom(
    String id, {
    int notificationCount = 0,
    Membership membership = Membership.join,
    bool space = false,
  }) {
    final room = Room(
      id: id,
      client: client,
      notificationCount: notificationCount,
      membership: membership,
    );
    if (space) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomCreate,
          content: {'type': RoomCreationTypes.mSpace},
          stateKey: '',
          senderId: client.userID!,
        ),
      );
    }
    client.rooms.add(room);
    return room;
  }

  test(
    'unreadRooms keeps unread and invited rooms, not read ones or spaces',
    () {
      addRoom('!unread:x', notificationCount: 2);
      addRoom('!invite:x', membership: Membership.invite);
      addRoom('!read:x');
      addRoom('!space:x', notificationCount: 1, space: true);

      final ids = client.unreadRooms.map((r) => r.id);

      expect(ids, containsAll(['!unread:x', '!invite:x']));
      expect(ids, isNot(contains('!read:x')));
      expect(ids, isNot(contains('!space:x')));
    },
  );

  Future<b.BadgeStyle> pumpBadge(WidgetTester tester, List<Room> rooms) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: UnreadRoomsBadge(rooms: rooms, child: const SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<b.Badge>(find.byType(b.Badge)).badgeStyle;
  }

  testWidgets('counts the rooms it is given, in primary', (tester) async {
    final style = await pumpBadge(tester, [
      addRoom('!a:x', notificationCount: 1),
      addRoom('!b:x', notificationCount: 1),
    ]);

    expect(find.text('2'), findsOneWidget);
    final context = tester.element(find.byType(UnreadRoomsBadge));
    expect(style.badgeColor, Theme.of(context).colorScheme.primary);
  });

  testWidgets('wears gold when a pending invite is among them', (tester) async {
    final style = await pumpBadge(tester, [
      addRoom('!a:x', notificationCount: 1),
      addRoom('!invite:x', membership: Membership.invite),
    ]);

    expect(find.text('2'), findsOneWidget);
    final context = tester.element(find.byType(UnreadRoomsBadge));
    expect(style.badgeColor, Theme.of(context).pangea.goldFixedDim);
  });
}
