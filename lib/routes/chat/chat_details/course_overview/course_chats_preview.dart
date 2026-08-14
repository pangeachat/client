import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/routes/chat_list/chat_list_item.dart';
import 'package:fluffychat/utils/stream_extension.dart';

/// The course page's Chats section highlight: the most recently active joined
/// chats in the course, capped at [maxChats]. The full list (discovery, open
/// sessions, admin chat suggestions) is the section's "All chats" subpage —
/// [CourseChats] — this preview only surfaces what the learner is already in.
class CourseChatsPreview extends StatelessWidget {
  final Room room;

  static const int maxChats = 2;

  const CourseChatsPreview({required this.room, super.key});

  /// Joined, non-space, non-session children of the course, in the client's
  /// recency order (client.rooms is sorted by latest activity).
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
              !r.isActivitySession,
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
        return Column(
          children: chats
              .map(
                (chat) => ChatListItem(
                  chat,
                  onTap: () => context.go(
                    WorkspaceNav.openRoomById(
                      GoRouterState.of(context).uri,
                      chat.id,
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
