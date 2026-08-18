import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_context_menu_action.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_attention_card.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/analytics_requests_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_requested_dialog.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// The course page's notifications section ("Catch up", #8357): a gold
/// attention card at the top of the page, rendered only when something needs
/// the user's attention — a bell with the count beside the section title.
///
/// Row sources, in order: analytics-access requests from course admins
/// (learner-side, via [AnalyticsRequestsBuilder]) and unread-message rollups
/// for the course's chats. Pending join requests are a decision rather than
/// something to catch up on, and live in their own card
/// (`CourseKnockRequests`, #8462).
class CourseCatchUp extends StatelessWidget {
  final Room room;

  const CourseCatchUp({required this.room, super.key});

  void _openChat(BuildContext context, Room chat) => context.go(
    WorkspaceNav.openRoomById(GoRouterState.of(context).uri, chat.id),
  );

  /// Mark all read clears the unread chats' indicators, and nothing else:
  /// a pending request is answered, never marked read (#8462).
  Future<void> _markAllRead(BuildContext context, List<Room> unreadChats) =>
      showFutureLoadingDialog(
        context: context,
        future: () =>
            Future.wait(unreadChats.map((chat) => chat.clearUnread())),
      );

  /// Joined, visible course chats with unread notifications — the same room
  /// set the Chats preview lists, narrowed to unreads.
  List<Room> get _unreadChats {
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
              !r.isHiddenRoom &&
              r.notificationCount > 0,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnalyticsRequestsBuilder(
      room: room,
      builder: (context, analyticsRequests) => StreamBuilder(
        stream: room.client.onSync.stream
            .where((s) => s.hasRoomUpdate)
            .rateLimit(const Duration(seconds: 1)),
        builder: (context, _) {
          final l10n = L10n.of(context);
          final unreadChats = _unreadChats;

          final rows = <Widget>[
            ...analyticsRequests.entries.map(
              (request) => _CatchUpAnalyticsRow(
                user: request.key,
                onTap: () => SpaceAnalyticsRequestedDialog.show(
                  context,
                  room,
                  analyticsRequests,
                ),
              ),
            ),
            ...unreadChats.map(
              (chat) => _CatchUpMessagesRow(
                chat: chat,
                onTap: () => _openChat(context, chat),
              ),
            ),
          ];

          return CourseAttentionCard(
            icon: Badge.count(
              count: rows.length,
              child: const Icon(
                Icons.notifications_outlined,
                size: CourseAttentionCard.iconSize,
              ),
            ),
            title: l10n.catchUp,
            actionLabel: l10n.markAllRead,
            onAction: () => _markAllRead(context, unreadChats),
            rows: rows,
          );
        },
      ),
    );
  }
}

/// One analytics-access request: the requesting admin, opening the
/// grant/deny review dialog.
class _CatchUpAnalyticsRow extends StatelessWidget {
  final User user;
  final VoidCallback onTap;

  const _CatchUpAnalyticsRow({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final displayname = user.localizedDisplayname(l10n);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        child: Row(
          children: [
            Avatar(mxContent: user.avatarUrl, name: displayname, size: 34.0),
            const SizedBox(width: 10.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    l10n.adminRequestedAccess,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.adaptive.arrow_forward_outlined, size: 16.0),
          ],
        ),
      ),
    );
  }
}

/// One unread-chat rollup: the new-message count over the chat's name,
/// opening the chat.
class _CatchUpMessagesRow extends StatelessWidget {
  final Room chat;
  final VoidCallback onTap;

  const _CatchUpMessagesRow({required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final displayname = chat.getLocalizedDisplayname(MatrixLocals(l10n));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        child: Row(
          children: [
            Avatar(mxContent: chat.avatar, name: displayname, size: 34.0),
            const SizedBox(width: 10.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.countNewMessages(chat.notificationCount),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    displayname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
