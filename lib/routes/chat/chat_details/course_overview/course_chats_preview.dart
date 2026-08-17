import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/routes/chat_list/course_default_chats_enum.dart';
import 'package:fluffychat/routes/chat_list/default_chat_creation_tile.dart';
import 'package:fluffychat/utils/stream_extension.dart';

/// The course page's Chats section highlight: the admin's default-chat
/// creation suggestions, then the most recently active joined chats in the
/// course — group chats and activity sessions alike — capped at [maxChats].
/// Discovery (unjoined chats, open sessions) stays on the section's "All
/// chats" subpage, [CourseChats].
class CourseChatsPreview extends StatelessWidget {
  final Room room;

  static const int maxChats = 2;

  const CourseChatsPreview({required this.room, super.key});

  /// Joined, visible, non-space children of the course — group chats AND
  /// activity-session chats — in the client's recency order (client.rooms is
  /// sorted by latest activity). Hidden rooms (analytics, archived
  /// activities) are filtered exactly as the full chat list filters them.
  List<Room> get _recentChats {
    final childIds = room.spaceChildren
        .map((child) => child.roomId)
        .whereType<String>()
        .toSet();
    return room.client.rooms
        .where(
          (r) =>
              childIds.contains(r.id) &&
              r.membership == Membership.join &&
              !r.isSpace &&
              !r.isHiddenRoom,
        )
        .take(maxChats)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: room.client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final chats = _recentChats;
        final titleFontSize = Theme.of(context).textTheme.bodyMedium?.fontSize;
        final subtitleFontSize = Theme.of(
          context,
        ).textTheme.bodySmall?.fontSize;
        return Column(
          children: [
            // The admin's create-introductions/announcements suggestions ride
            // the preview too — an admin who never opens "All chats" must
            // still see them. Both self-hide once created or dismissed.
            for (final type in CourseDefaultChatsEnum.values)
              DefaultChatCreationTile(
                space: room,
                type: type,
                titleFontSize: titleFontSize,
                subtitleFontSize: subtitleFontSize,
              ),
            ...chats.map(
              (chat) => ChatListItem(
                chat,
                titleFontSize: titleFontSize,
                subtitleFontSize: subtitleFontSize,
                onTap: () => context.go(
                  WorkspaceNav.openRoomById(
                    GoRouterState.of(context).uri,
                    chat.id,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
