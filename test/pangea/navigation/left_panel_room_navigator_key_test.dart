import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_room_subpage.dart';

void main() {
  group('chatPanelNavigatorId (#8142)', () {
    const roomId = '!abc:example.com';

    test('each room-panel token type gets its own Navigator identity', () {
      // The same room can reopen under a different token: `room` from the chat
      // list, then `session` from the Stars archive after the activity ends.
      // One shared id let the session panel GlobalKey-reparent the room
      // panel's Navigator, preserving the stale route whose close button
      // dropped the departed `room` token — a no-op on the live URL, so the
      // back button did nothing. Distinct ids force a fresh ChatPage (and a
      // close button bound to the live token) on a cross-type swap.
      final ids = {
        for (final type in PanelTypesEnum.values.where((t) => t.isRoomPanel))
          type: chatPanelNavigatorId(type, roomId),
      };
      expect(
        ids.values.toSet().length,
        ids.length,
        reason: 'room/session/archivedroom must not share a Navigator id: $ids',
      );
    });

    test('the id is stable for the same token type and room', () {
      // Same-type stability is the key's original job: a slot move repositions
      // the same ChatController instead of remounting it.
      expect(
        chatPanelNavigatorId(PanelTypesEnum.room, roomId),
        chatPanelNavigatorId(PanelTypesEnum.room, roomId),
      );
    });

    test('different rooms of one type never collide', () {
      expect(
        chatPanelNavigatorId(PanelTypesEnum.room, '!a:example.com'),
        isNot(chatPanelNavigatorId(PanelTypesEnum.room, '!b:example.com')),
      );
    });
  });
}
