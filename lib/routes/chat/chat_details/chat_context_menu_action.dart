import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/course_image_builder.dart';
import 'package:fluffychat/pangea/extensions/leave_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_space_dialog.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/utils/chat_download_provider.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// Which surface a chat's action menu was opened from. All of them offer the
/// same actions on the room and differ only at the ends: [chatList] leads with
/// the chat itself and, after a leave or delete, closes just that row's panel
/// so the list survives; [chatHeader] leads with search and chat details — the
/// surfaces the header used to expose as separate icons — plus a session's
/// Invite and Download. [chatHeader] and [startPage] are the room's own
/// surface, so a leave or delete there falls back to the workspace exit and
/// the learner is never left looking at a room they left. [startPage] carries
/// none of the header's extras: its waiting room already has an invite button,
/// and there is no chat yet to search.
enum ChatMenuSource { chatList, chatHeader, startPage }

extension on ChatContextAction {
  bool enabled({
    required Room room,
    required Room? space,
    required ChatMenuSource source,
  }) {
    switch (this) {
      case ChatContextAction.open:
        return source == ChatMenuSource.chatList;
      case ChatContextAction.search:
      case ChatContextAction.details:
        return source == ChatMenuSource.chatHeader;
      case ChatContextAction.invite:
        // A session that has ended for everyone can no longer be joined.
        return source == ChatMenuSource.chatHeader &&
            room.isActivitySession &&
            !room.isActivityFinished;
      case ChatContextAction.download:
        // Any member may export a transcript. Web/desktop only for now — the
        // native mobile download path is unvalidated. A regular chat exports
        // from its details button row instead.
        return source == ChatMenuSource.chatHeader &&
            room.isActivitySession &&
            kIsWeb;
      case ChatContextAction.goToSpace:
        return space != null;
      case ChatContextAction.favorite:
      case ChatContextAction.markUnread:
        return room.membership == Membership.join && !room.isActivitySession;
      case ChatContextAction.mute:
        return room.membership == Membership.join;
      case ChatContextAction.leave:
        if (room.membership != Membership.join) return false;
        if (!room.isActivitySession) return true;
        return !room.isActivityStarted || !room.hasPickedRole;
      case ChatContextAction.delete:
        return room.isRoomAdmin && !room.isDirectChat;
      case ChatContextAction.endActivity:
        return room.isActiveInActivity && room.isActivityStarted;
      default:
        return false;
    }
  }
}

extension RoomUnreadContextActions on Room {
  /// Whether the chat list is currently showing an unread indicator for this
  /// room — the same predicate `UnreadBubble` draws from. Note this is wider
  /// than [markedUnread] (the explicit `m.marked_unread` flag): a room with
  /// real unread messages, or a muted room with new ones, is unread without
  /// that flag ever being set.
  bool get showsUnreadIndicator => isUnread || hasNewMessages;

  /// Clears the unread indicator: sends a read receipt (what actually drops
  /// `notificationCount`, and with it the badge count) and clears the explicit
  /// unread flag. [markUnread] alone does **not** set a read marker, so on its
  /// own it leaves the count untouched.
  ///
  /// Receipt targeting is delegated to the timeline, which picks the newest
  /// *synced* event. That skips an unsent local echo — whose id is a
  /// transaction id the server would reject a receipt for — and still marks
  /// the confirmed messages beneath it read. Same path the chat view takes on
  /// open.
  Future<void> clearUnread() async {
    final timeline = await getTimeline();
    try {
      await timeline.setReadMarker(
        public: AppSettings.sendPublicReadReceipts.value,
      );
    } finally {
      timeline.cancelSubscriptions();
    }
    if (markedUnread) await markUnread(false);
  }
}

/// The one list of actions a chat offers, shared by the chat-list row's
/// long-press menu and the chat header's More menu so neither can drift into
/// offering something the other does not.
List<PopupMenuEntry<ChatContextAction>> chatContextMenuItems(
  BuildContext context, {
  required Room room,
  required ChatMenuSource source,
  Room? space,
}) {
  final theme = Theme.of(context);
  final l10n = L10n.of(context);
  final displayname = room.getLocalizedDisplayname(MatrixLocals(l10n));

  bool on(ChatContextAction action) =>
      action.enabled(room: room, space: space, source: source);

  // What the menu opens with: on a chat-list row the chat itself, in the chat
  // header the two surfaces its icon buttons used to open.
  final leading = <PopupMenuEntry<ChatContextAction>>[
    if (on(ChatContextAction.open))
      PopupMenuItem(
        value: ChatContextAction.open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 12.0,
          children: [
            Avatar(
              mxContent: room.avatar,
              name: displayname,
              userId: room.directChatMatrixID,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 128),
              child: Text(
                displayname,
                style: TextStyle(color: theme.colorScheme.onSurface),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    if (on(ChatContextAction.search))
      PopupMenuItem(
        value: ChatContextAction.search,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_outlined),
            const SizedBox(width: 12),
            Text(l10n.search),
          ],
        ),
      ),
    if (on(ChatContextAction.details))
      PopupMenuItem(
        value: ChatContextAction.details,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: 12),
            Text(l10n.chatDetails),
          ],
        ),
      ),
    if (on(ChatContextAction.invite))
      PopupMenuItem(
        value: ChatContextAction.invite,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_add_outlined),
            const SizedBox(width: 12),
            Text(l10n.invite),
          ],
        ),
      ),
    if (on(ChatContextAction.download))
      PopupMenuItem(
        value: ChatContextAction.download,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_outlined),
            const SizedBox(width: 12),
            Text(l10n.download),
          ],
        ),
      ),
  ];

  final actions = <PopupMenuEntry<ChatContextAction>>[
    if (on(ChatContextAction.goToSpace))
      PopupMenuItem(
        value: ChatContextAction.goToSpace,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CourseImageBuilder.room(
              room: space!,
              builder: (context, image) => Avatar(
                mxContent: image,
                size: Avatar.defaultSize / 2,
                name: space.getLocalizedDisplayname(),
                userId: space.directChatMatrixID,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n.goToCourse(space.getLocalizedDisplayname())),
            ),
          ],
        ),
      ),
    if (on(ChatContextAction.mute))
      PopupMenuItem(
        value: ChatContextAction.mute,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              room.pushRuleState == PushRuleState.notify
                  ? Icons.notifications_on_outlined
                  : Icons.notifications_off_outlined,
            ),
            const SizedBox(width: 12),
            Text(
              room.pushRuleState == PushRuleState.notify
                  ? l10n.notificationsOn
                  : l10n.notificationsOff,
            ),
          ],
        ),
      ),
    if (on(ChatContextAction.markUnread))
      PopupMenuItem(
        value: ChatContextAction.markUnread,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              room.showsUnreadIndicator
                  ? Icons.mark_as_unread
                  : Icons.mark_as_unread_outlined,
            ),
            const SizedBox(width: 12),
            Text(
              room.showsUnreadIndicator ? l10n.markAsRead : l10n.markAsUnread,
            ),
          ],
        ),
      ),
    if (on(ChatContextAction.favorite))
      PopupMenuItem(
        value: ChatContextAction.favorite,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(room.isFavourite ? Icons.push_pin : Icons.push_pin_outlined),
            const SizedBox(width: 12),
            Text(room.isFavourite ? l10n.unpin : l10n.pin),
          ],
        ),
      ),
    if (on(ChatContextAction.endActivity))
      PopupMenuItem(
        value: ChatContextAction.endActivity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stop_circle_outlined),
            const SizedBox(width: 12),
            Text(l10n.endActivity),
          ],
        ),
      ),
    if (on(ChatContextAction.leave))
      PopupMenuItem(
        value: ChatContextAction.leave,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.logout_outlined,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Text(
              l10n.leave,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ],
        ),
      ),
    if (on(ChatContextAction.delete))
      PopupMenuItem(
        value: ChatContextAction.delete,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outlined,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Text(
              l10n.delete,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ],
        ),
      ),
  ];

  return [
    ...leading,
    if (leading.isNotEmpty && actions.isNotEmpty) const PopupMenuDivider(),
    ...actions,
  ];
}

/// Runs a chosen [action] against [room].
///
/// [context] raises dialogs while the menu's own surface is still on screen;
/// [outerContext] is the surface that outlives the room going away, so leave
/// and delete navigate from it.
Future<void> handleChatContextAction(
  ChatContextAction action, {
  required BuildContext context,
  required BuildContext outerContext,
  required Room room,
  required ChatMenuSource source,
  Room? space,
  VoidCallback? onChatTap,
}) async {
  final l10n = L10n.of(context);

  /// Where a leave or delete leaves the learner: a chat-list row drops only
  /// that room's panel so the list survives, while the room's own surface has
  /// to send them somewhere else entirely.
  void closeRoom(BuildContext context) => source == ChatMenuSource.chatList
      ? closeRoomPanelFromList(context, room.id)
      : closeOwnRoomPanel(context, room.id);

  /// Waits for a leave or delete to land in sync, so the room is gone from the
  /// chat list before its panel closes. The room's own surface can unmount
  /// while that happens — the room it shows is going away — so the result says
  /// whether [outerContext] is still there to navigate from.
  Future<bool> settled() async {
    final r = room.client.getRoomById(room.id);
    if (r != null && r.membership != Membership.leave) {
      await room.client.waitForRoomInSync(room.id, leave: true);
    }
    return outerContext.mounted;
  }

  switch (action) {
    case ChatContextAction.open:
      onChatTap?.call();
      return;
    case ChatContextAction.search:
      NavigationUtil.goToSpaceRoute(room.id, ['search'], context);
      return;
    case ChatContextAction.details:
      // Toggle: the header's settings icon closed an open details page, and
      // the menu item that replaced it keeps that behaviour.
      GoRouterState.of(context).uri.path.endsWith('/details')
          ? NavigationUtil.goToSpaceRoute(room.id, [], context)
          : NavigationUtil.goToSpaceRoute(room.id, ['details'], context);
      return;
    case ChatContextAction.invite:
      NavigationUtil.goToSpaceRoute(room.id, ['invite'], context);
      return;
    case ChatContextAction.download:
      await showChatDownloadDialog(room.id, context);
      return;
    case ChatContextAction.goToSpace:
      // world_v2: token nav to the course card (sets ?m=course:<id>&left=course),
      // not the legacy /rooms/spaces path.
      outerContext.go(
        WorkspaceNav.openCourse(GoRouterState.of(outerContext).uri, space!.id),
      );
      return;
    case ChatContextAction.favorite:
      await showFutureLoadingDialog(
        context: context,
        future: () => room.setFavourite(!room.isFavourite),
      );
      return;
    case ChatContextAction.markUnread:
      // Re-read the predicate rather than reusing the value the menu was built
      // from — a message can arrive while the menu is open.
      final markRead = room.showsUnreadIndicator;
      await showFutureLoadingDialog(
        context: context,
        future: () => markRead ? room.clearUnread() : room.markUnread(true),
      );
      return;
    case ChatContextAction.mute:
      await showFutureLoadingDialog(
        context: context,
        future: () => room.setPushRuleState(
          room.pushRuleState == PushRuleState.notify
              ? PushRuleState.mentionsOnly
              : PushRuleState.notify,
        ),
      );
      return;
    case ChatContextAction.block:
      final inviteEvent = room.getState(
        EventTypes.RoomMember,
        room.client.userID!,
      );
      final blockUser = inviteEvent?.senderId;
      context.go(
        WorkspaceNav.openSettings(
          GoRouterState.of(context).uri,
          page: blockUser == null
              ? 'security/ignorelist'
              : 'security/ignorelist/$blockUser',
        ),
      );
    case ChatContextAction.leave:
      final confirmed = await showOkCancelAlertDialog(
        context: outerContext,
        title: l10n.areYouSure,
        message: room.isSpace
            ? l10n.leaveSpaceDescription
            : l10n.leaveRoomDescription,
        okLabel: l10n.leave,
        cancelLabel: l10n.cancel,
        isDestructive: true,
      );
      if (confirmed != OkCancelResult.ok || !outerContext.mounted) return;

      final isSpace = room.isSpace;
      // An old session the homeserver has forgotten answers /leave with a 404
      // that is not a failure — the learner is out of it either way (#8234).
      final resp = await showFutureLoadingDialog(
        context: outerContext,
        future: isSpace
            ? room.leaveSpace
            : room.isActivitySession
            ? room.leaveIgnoringUnknownRoom
            : room.leave,
      );

      // A failed leave never lands in sync, so waiting for it would only stall.
      if (resp.isError || !await settled()) return;

      // Leaving a whole course is the World/home reset: drop every panel and
      // the `?c=` scope, back to the world map at its personal default. A
      // chat/DM/activity instead just drops its own panel.
      isSpace
          ? outerContext.go(WorkspaceNav.clearAll())
          : closeRoom(outerContext);
      return;
    case ChatContextAction.delete:
      if (room.isSpace) {
        await DeleteSpaceDialog.show(room, outerContext);
      } else {
        final confirmed = await showOkCancelAlertDialog(
          context: outerContext,
          title: l10n.areYouSure,
          okLabel: l10n.delete,
          cancelLabel: l10n.cancel,
          isDestructive: true,
          message: room.isSpace ? l10n.deleteSpaceDesc : l10n.deleteChatDesc,
        );
        if (confirmed != OkCancelResult.ok || !outerContext.mounted) return;
        final resp = await showFutureLoadingDialog(
          context: outerContext,
          future: room.delete,
        );
        if (resp.isError || !await settled()) return;
        closeRoom(outerContext);
      }
      return;
    case ChatContextAction.endActivity:
      await showFutureLoadingDialog(
        context: outerContext,
        future: room.finishActivity,
      );
      return;
  }
}

void chatContextMenuAction(
  Room room,
  BuildContext context,
  BuildContext outerContext,
  VoidCallback onChatTap, [
  Room? space,
]) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  final button = context.findRenderObject() as RenderBox;

  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(const Offset(0, -65), ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero) + const Offset(-50, 0),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );

  final action = await showMenu<ChatContextAction>(
    context: context,
    position: position,
    items: chatContextMenuItems(
      context,
      room: room,
      space: space,
      source: ChatMenuSource.chatList,
    ),
  );

  if (action == null || !context.mounted) return;

  await handleChatContextAction(
    action,
    context: context,
    outerContext: outerContext,
    room: room,
    space: space,
    source: ChatMenuSource.chatList,
    onChatTap: onChatTap,
  );
}
