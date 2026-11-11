import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/unread_bubble.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'get_test_client.dart';

/// #8007 — the unread bubble is a fixed-size circle, not a pill that widens
/// with the count. It shares a chat list row with the room name and last
/// message, and a stretching bubble squeezed them; it also read as a different
/// shape from the All-Chats nav badge next to it.
void main() {
  late Client client;

  const roomId = '!1234:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  Room unreadRoom({required int notificationCount, int highlightCount = 0}) =>
      Room(
        id: roomId,
        client: client,
        notificationCount: notificationCount,
        highlightCount: highlightCount,
      );

  /// Builds [room]'s bubble without settling, so a test can step through its
  /// animation.
  Future<void> mountBubble(
    WidgetTester tester,
    Room room, {
    Color? borderColor,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      // Unconstrained so the bubble reports the size it asks for, not one a
      // parent forced on it.
      home: Scaffold(
        body: Center(
          child: UnreadBubble(room: room, borderColor: borderColor),
        ),
      ),
    ),
  );

  Future<Size> pumpBubble(
    WidgetTester tester,
    Room room, {
    Color? borderColor,
  }) async {
    await mountBubble(tester, room, borderColor: borderColor);
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(UnreadBubble));
  }

  /// Whether a canvas call puts a circle on screen: a stroked ring, or a
  /// filled disc with a positive radius. A zero-radius fill covers no pixels.
  bool isVisibleCircle(Symbol method, List<dynamic> arguments) =>
      method == #drawCircle &&
      ((arguments[1] as double) > 0 ||
          (arguments[2] as Paint).style == PaintingStyle.stroke);

  final paintsNoVisibleCircle = anyOf(
    paintsNothing,
    paints
      ..everything((method, arguments) => !isVisibleCircle(method, arguments)),
  );

  testWidgets('a one-digit count renders a circle', (tester) async {
    final size = await pumpBubble(tester, unreadRoom(notificationCount: 8));
    expect(size.width, size.height);
  });

  testWidgets('the circle does not grow with the number of digits', (
    tester,
  ) async {
    final one = await pumpBubble(tester, unreadRoom(notificationCount: 8));
    final two = await pumpBubble(tester, unreadRoom(notificationCount: 42));
    final three = await pumpBubble(tester, unreadRoom(notificationCount: 999));

    expect(two, one);
    expect(three, one);
  });

  testWidgets('counts past 99 read as 99+, like the nav badge', (tester) async {
    await pumpBubble(tester, unreadRoom(notificationCount: 128));
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('128'), findsNothing);
  });

  testWidgets('the count text stays inside the circle', (tester) async {
    // A FittedBox shrinks the widest count to fit, so nothing paints outside
    // the circle's box.
    await pumpBubble(tester, unreadRoom(notificationCount: 999));
    final bubble = tester.getRect(find.byType(UnreadBubble));
    final text = tester.getRect(find.text('99+'));

    expect(bubble.contains(text.topLeft), isTrue);
    expect(bubble.contains(text.bottomRight), isTrue);
  });

  testWidgets('an unread room with no count renders the plain dot', (
    tester,
  ) async {
    final room = unreadRoom(notificationCount: 0);
    room.roomAccountData['m.marked_unread'] = BasicEvent(
      type: 'm.marked_unread',
      content: {'unread': true},
    );

    final size = await pumpBubble(tester, room);
    expect(size.width, size.height);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a read room renders nothing', (tester) async {
    final size = await pumpBubble(tester, unreadRoom(notificationCount: 0));
    expect(size, Size.zero);
  });

  // #9416: the map pins and the large card ring the bubble in white, and the
  // ringed bubble of a read room still painted a 1.5px dot in its fill colour.
  testWidgets('a read room paints nothing, even with the map pins\' ring', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      unreadRoom(notificationCount: 0),
      borderColor: PinSize.markRing,
    );
    expect(find.byType(UnreadBubble), paintsNoVisibleCircle);
  });

  testWidgets('reading a room shrinks its ringed bubble away to nothing', (
    tester,
  ) async {
    final room = unreadRoom(notificationCount: 3);
    await pumpBubble(tester, room, borderColor: PinSize.markRing);

    room.notificationCount = 0;
    await mountBubble(tester, room, borderColor: PinSize.markRing);
    // Halfway through, the bubble is still on screen, closing rather than
    // gone at once.
    await tester.pump(FluffyThemes.animationDuration ~/ 2);
    expect(find.byType(UnreadBubble), paints..something(isVisibleCircle));

    await tester.pumpAndSettle();
    expect(find.byType(UnreadBubble), paintsNoVisibleCircle);
  });

  testWidgets('the count survives the open animation without overflowing', (
    tester,
  ) async {
    // The circle animates open from zero width, so the count is briefly laid
    // out in a box narrower than itself. The FittedBox has to absorb that
    // rather than paint outside the circle.
    final room = unreadRoom(notificationCount: 0);
    await pumpBubble(tester, room);

    room.notificationCount = 999;
    await mountBubble(tester, room);
    // Step through the growth rather than settling straight to the end state.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
