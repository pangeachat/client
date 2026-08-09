import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

/// Behavioral coverage for the leave/delete close helpers (#7561): leaving or
/// deleting a chat must close ONLY that chat's panel and never the list it sits
/// in. `closeRoomPanelFromList` drives the chat-list / course-chat-list context
/// menus; `closeOwnRoomPanel` drives the chat's own in-view menu and details
/// page. Both delegate to `roomTokenCloseLocation` (unit-tested separately in
/// activity_room_close_test.dart) — here we pin the navigate-vs-no-op contract
/// that the earlier bug got wrong.
void main() {
  /// Pump a GoRouter at [initialLocation], invoke [onTap] with the button's
  /// (in-shell) context, and return the resulting location after it settles.
  Future<Uri> tapClose(
    WidgetTester tester,
    String initialLocation,
    void Function(BuildContext) onTap,
  ) async {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => onTap(context),
              child: const Text('close'),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    return router.routerDelegate.currentConfiguration.uri;
  }

  group('closeRoomPanelFromList — leaving from a list row (#7561)', () {
    testWidgets('leaving an open chat keeps the chat list', (tester) async {
      final uri = await tapClose(
        tester,
        '/?left=chats,room:!abc',
        (c) => closeRoomPanelFromList(c, '!abc'),
      );
      final left = parseOpenPanels(uri).left.map((t) => t.type);
      expect(left, [PanelTypesEnum.chats]); // list survives, room dropped
    });

    testWidgets('leaving an open chat from a course-scoped list keeps the '
        'course card and the course context', (tester) async {
      final uri = await tapClose(
        tester,
        '/?c=!course&left=course,room:!abc',
        (c) => closeRoomPanelFromList(c, '!abc'),
      );
      expect(parseOpenPanels(uri).left.map((t) => t.type), [
        PanelTypesEnum.course,
      ]);
      expect(activeSpaceIdFor(uri), '!course'); // scope survives
    });

    testWidgets('leaving a chat that is NOT open does not navigate — the chat '
        'list stays exactly as it was', (tester) async {
      final uri = await tapClose(
        tester,
        '/?left=chats',
        (c) => closeRoomPanelFromList(c, '!notopen'),
      );
      // The pre-fix bug: an unconditional goToSpaceRoute here cleared the list
      // to the bare world map. There is nothing to close, so nothing moves.
      expect(uri.toString(), '/?left=chats');
    });

    testWidgets('leaving a chat that is NOT open from a course-scoped list '
        'leaves that list untouched', (tester) async {
      final uri = await tapClose(
        tester,
        '/?c=!course&left=course',
        (c) => closeRoomPanelFromList(c, '!notopen'),
      );
      expect(parseOpenPanels(uri).left.map((t) => t.type), [
        PanelTypesEnum.course,
      ]);
      expect(activeSpaceIdFor(uri), '!course');
    });
  });

  group('closeOwnRoomPanel — leaving from the chat\'s own surface (#7561)', () {
    testWidgets(
      'leaving the open chat drops its panel, keeping the chat list',
      (tester) async {
        final uri = await tapClose(
          tester,
          '/?left=chats,room:!abc',
          (c) => closeOwnRoomPanel(c, '!abc'),
        );
        expect(parseOpenPanels(uri).left.map((t) => t.type), [
          PanelTypesEnum.chats,
        ]);
      },
    );

    testWidgets('falls back to the bare workspace exit when the room is not a '
        'token panel', (tester) async {
      final uri = await tapClose(
        tester,
        '/?left=chats',
        (c) => closeOwnRoomPanel(c, '!notopen'),
      );
      // No matching room token -> the defensive fallback exits to the world map
      // rather than stranding the user on the room they just left.
      expect(uri.path, '/');
      expect(parseOpenPanels(uri).left, isEmpty);
      expect(activeSpaceIdFor(uri), isNull);
    });
  });
}
