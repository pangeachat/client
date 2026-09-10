import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
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
/// Row sources, in order: the course ping a coursemate sent to gather players
/// (#8944), analytics-access requests from course admins (learner-side, via
/// [AnalyticsRequestsBuilder]) and unread-message rollups for the course's
/// chats. Pending join requests are a decision rather than something to catch
/// up on, and live in their own card (`CourseKnockRequests`, #8462).
///
/// The ping leads because it is the only row with a clock on it — a session
/// is being filled right now, while a request or an unread message keeps.
/// That matters here specifically: the card shows two rows before its
/// expander, so order decides what a learner sees without tapping.
class CourseCatchUp extends StatelessWidget {
  final Room room;

  const CourseCatchUp({required this.room, super.key});

  void _openChat(BuildContext context, Room chat) => context.go(
    WorkspaceNav.openRoomById(GoRouterState.of(context).uri, chat.id),
  );

  /// Open the pinged activity bound to the session the ping named, so the
  /// learner lands on the seat the host was recruiting for rather than on a
  /// fresh session of the same activity. Immersive in-course open, the same
  /// producer the course plan's cards use.
  void _openPingedActivity(BuildContext context, CoursePingBadgeData ping) {
    CoursePingBadgeCache.markFollowed(ping.activityId);
    context.go(
      WorkspaceNav.openCourseActivity(
        room.id,
        ping.activityId,
        roomId: ping.sessionRoomId,
      ),
    );
  }

  /// The ping this course is currently carrying, or null. A learner's own
  /// ping never reaches the cache ([CoursePingRoomExtension.unreadCoursePingEvent]
  /// filters it), so this is always somebody else's.
  CoursePingBadgeData? _pingFor(CoursePingBadgeData? ping) =>
      ping != null && ping.courseId == room.id ? ping : null;

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
    return ValueListenableBuilder(
      valueListenable: CoursePingBadgeCache.instance,
      builder: (context, cachedPing, _) => AnalyticsRequestsBuilder(
        room: room,
        builder: (context, analyticsRequests) => StreamBuilder(
          stream: room.client.onSync.stream
              .where((s) => s.hasRoomUpdate)
              .rateLimit(const Duration(seconds: 1)),
          builder: (context, _) {
            final l10n = L10n.of(context);
            final unreadChats = _unreadChats;
            final ping = _pingFor(cachedPing);

            final rows = <Widget>[
              if (ping != null)
                _CatchUpPingRow(
                  room: room,
                  ping: ping,
                  onTap: () => _openPingedActivity(context, ping),
                ),
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
      ),
    );
  }
}

/// The course ping a coursemate sent to gather players for their session
/// (#8944), opening that activity on the session the ping named.
///
/// Names both halves of what a ping is — WHICH activity, and WHO is waiting in
/// it — because either alone leaves the learner deciding blind: an activity
/// with no host does not say anyone is actually there, and a host with no
/// activity does not say what they are asking for.
///
/// The activity title is hydrated through [ActivityPlanRepo] the same way
/// every other surface holding only an activity id does; the ping event
/// carries ids, not a title. The row renders without it while that lands, so
/// a slow plan fetch delays the name, never the row.
class _CatchUpPingRow extends StatelessWidget {
  final Room room;
  final CoursePingBadgeData ping;
  final VoidCallback onTap;

  const _CatchUpPingRow({
    required this.room,
    required this.ping,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final sender = room.unsafeGetUserFromMemoryOrFallback(ping.senderId);
    final senderName = sender.localizedDisplayname(l10n);
    return ListenableBuilder(
      listenable: ActivityPlanRepo.instance,
      builder: (context, _) {
        // No-op once cached; the repo listener above rebuilds when it lands.
        ActivityPlanRepo.instance.ensure(ping.activityId);
        final title = ActivityPlanRepo.instance
            .cachedPlan(ping.activityId)
            ?.title;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5.0),
            child: Row(
              children: [
                // The sender's own avatar, marked with the app's one ping
                // glyph — the same pairing the course avatar wears in the nav
                // rail, so a ping looks like a ping wherever it is met.
                Semantics(
                  label: l10n.pingedLabel,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Avatar(
                        mxContent: sender.avatarUrl,
                        name: senderName,
                        size: 34.0,
                      ),
                      const Positioned(
                        right: -2.0,
                        bottom: -2.0,
                        child: CoursePingBadge(size: 16.0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? l10n.pingedActivity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
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
      },
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
