import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

void main() {
  Uri u(String s) => Uri.parse(s);

  group('roomTokenCloseLocation (#7156, #7561)', () {
    test('closing a room-token activity drops only the room, keeping the '
        'chat list', () {
      final loc = roomTokenCloseLocation(u('/?left=chats,room:!abc'), '!abc');
      expect(loc, isNotNull);
      final left = parseOpenPanels(u(loc!)).left;
      expect(
        left.any((t) => t.type == PanelTypesEnum.chats),
        isTrue,
      ); // chat list survives
      expect(
        left.any((t) => t.type == PanelTypesEnum.room),
        isFalse,
      ); // room dropped
    });

    test('other open panels survive (e.g. an analytics summary)', () {
      final loc = roomTokenCloseLocation(
        u('/?left=chats,room:!abc&right=analytics:vocab'),
        '!abc',
      );
      final panels = parseOpenPanels(u(loc!));
      expect(panels.left.map((t) => t.type), [PanelTypesEnum.chats]);
      expect(
        panels.right.any((t) => t.type == PanelTypesEnum.analytics),
        isTrue,
      );
    });

    test('leaving a chat opened from the chat list keeps the list and the '
        'course context (#7561)', () {
      final loc = roomTokenCloseLocation(
        u('/?c=!course&left=chats,room:!abc'),
        '!abc',
      );
      expect(loc, isNotNull);
      final closed = u(loc!);
      expect(parseOpenPanels(closed).left.map((t) => t.type), [
        PanelTypesEnum.chats,
      ]);
      expect(activeSpaceIdFor(closed), '!course'); // map scope survives
    });

    test('the standalone /<activityId> route has no room token, so it returns '
        'null (caller pops or falls back to home)', () {
      expect(roomTokenCloseLocation(u('/abc123'), '!abc'), isNull);
    });
  });
}
