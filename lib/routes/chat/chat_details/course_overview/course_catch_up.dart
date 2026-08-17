import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/analytics_requests_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_requested_dialog.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// The course page's notifications section ("Catch up", #8357): a gold
/// attention card at the top of the page, rendered only when something needs
/// the user's attention — a bell with the count beside the section title,
/// rows capped at [_maxCollapsedRows] with a load-more expander so a pile of
/// notifications never overwhelms the page.
///
/// Row sources, in order: join requests (admin-only, via
/// [KnockingUsersBuilder]), analytics-access requests from course admins
/// (learner-side, via [AnalyticsRequestsBuilder]), and unread-message
/// rollups for the course's chats.
class CourseCatchUp extends StatefulWidget {
  final Room room;

  const CourseCatchUp({required this.room, super.key});

  @override
  State<CourseCatchUp> createState() => _CourseCatchUpState();
}

class _CourseCatchUpState extends State<CourseCatchUp> {
  static const int _maxCollapsedRows = 2;

  bool _expanded = false;

  /// Approve routes through the existing invite page seated on the knock
  /// filter — the reviewed accept/deny flow (#8139).
  void _openKnockReview(BuildContext context) => context.go(
    WorkspaceNav.openCoursePage(
      GoRouterState.of(context).uri,
      RoomSubpageEnum.invite,
      filter: InvitationFilter.knocking,
    ),
  );

  void _openChat(BuildContext context, Room chat) => context.go(
    WorkspaceNav.openRoomById(GoRouterState.of(context).uri, chat.id),
  );

  /// Joined, visible course chats with unread notifications — the same room
  /// set the Chats preview lists, narrowed to unreads.
  List<Room> get _unreadChats {
    final childIds = widget.room.spaceChildren
        .map((child) => child.roomId)
        .whereType<String>()
        .toSet();
    return widget.room.client.rooms
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
    return KnockingUsersBuilder(
      room: widget.room,
      builder: (context, knockingUsers) => AnalyticsRequestsBuilder(
        room: widget.room,
        builder: (context, analyticsRequests) => StreamBuilder(
          stream: widget.room.client.onSync.stream
              .where((s) => s.hasRoomUpdate)
              .rateLimit(const Duration(seconds: 1)),
          builder: (context, _) {
            final l10n = L10n.of(context);
            final rows = <Widget>[
              ...knockingUsers.map(
                (user) => _CatchUpKnockRow(
                  user: user,
                  onApprove: () => _openKnockReview(context),
                ),
              ),
              ...analyticsRequests.keys.map(
                (user) => _CatchUpAnalyticsRow(
                  user: user,
                  onTap: () => SpaceAnalyticsRequestedDialog.show(
                    context,
                    widget.room,
                    analyticsRequests,
                  ),
                ),
              ),
              ..._unreadChats.map(
                (chat) => _CatchUpMessagesRow(
                  chat: chat,
                  onTap: () => _openChat(context, chat),
                ),
              ),
            ];
            if (rows.isEmpty) return const SizedBox.shrink();

            final visible = _expanded
                ? rows
                : rows.take(_maxCollapsedRows).toList();
            final hiddenCount = rows.length - visible.length;
            final gold = AppConfig.goldByTheme(context);
            return Semantics(
              label: l10n.catchUp,
              container: true,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: gold.withAlpha(30),
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Badge.count(
                          count: rows.length,
                          child: const Icon(
                            Icons.notifications_outlined,
                            size: 20.0,
                          ),
                        ),
                        const SizedBox(width: 10.0),
                        Text(
                          l10n.catchUp,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.0),
                    ...visible,
                    if (hiddenCount > 0)
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() => _expanded = true),
                          child: Text(
                            l10n.loadMore,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One join request: the knocking user's avatar and name, with an Approve
/// action opening the knock-review flow.
class _CatchUpKnockRow extends StatelessWidget {
  final User user;
  final VoidCallback onApprove;

  const _CatchUpKnockRow({required this.user, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final displayname = user.localizedDisplayname(l10n);
    return Padding(
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
                  l10n.knocking,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onApprove,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(
              l10n.approve,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
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
