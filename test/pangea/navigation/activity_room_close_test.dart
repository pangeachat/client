import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_sessions_start_view.dart';

void main() {
  Uri u(String s) => Uri.parse(s);

  group('activityRoomCloseLocation (#7156)', () {
    test('closing a room-token activity drops only the room, keeping the '
        'chat list', () {
      final loc = activityRoomCloseLocation(
        u('/?left=chats,room:!abc'),
        '!abc',
      );
      expect(loc, isNotNull);
      final left = parseOpenPanels(u(loc!)).left;
      expect(left.any((t) => t.type == 'chats'), isTrue); // chat list survives
      expect(left.any((t) => t.type == 'room'), isFalse); // room dropped
    });

    test('other open panels survive (e.g. an analytics summary)', () {
      final loc = activityRoomCloseLocation(
        u('/?left=chats,room:!abc&right=analytics:vocab'),
        '!abc',
      );
      final panels = parseOpenPanels(u(loc!));
      expect(panels.left.map((t) => t.type), ['chats']);
      expect(panels.right.any((t) => t.type == 'analytics'), isTrue);
    });

    test('the standalone /<activityId> route has no room token, so it returns '
        'null (caller pops or falls back to home)', () {
      expect(activityRoomCloseLocation(u('/abc123'), '!abc'), isNull);
    });
  });
}
