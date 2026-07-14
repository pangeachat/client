import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_space_dialog.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

extension on ChatContextAction {
  bool enabled({required Room room, required Room? space}) {
    switch (this) {
      case ChatContextAction.open:
        return true;
      case ChatContextAction.goToSpace:
        return space != null;
      case ChatContextAction.favorite:
      case ChatContextAction.markUnread:
        return room.membership == Membership.join && !room.isActivitySession;
      case ChatContextAction.mute:
        return room.membership == Membership.join;
      case ChatContextAction.leave:
        return room.membership == Membership.join &&
            (!room.isActivitySession || !room.isActivityStarted);
      case ChatContextAction.delete:
        return room.isRoomAdmin && !room.isDirectChat;
      case ChatContextAction.endActivity:
        return room.isActiveInActivity && room.isActivityStarted;
      default:
        return false;
    }
  }
}

void chatContextMenuAction(
  Room room,
  BuildContext context,
  BuildContext outerContext,
  VoidCallback onChatTap, [
  Room? space,
]) async {
  final theme = Theme.of(context);
  final l10n = L10n.of(context);

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

  final displayname = room.getLocalizedDisplayname(MatrixLocals(l10n));
  final enabledCount = ChatContextAction.values
      .where((v) => v.enabled(room: room, space: space))
      .length;

  final action = await showMenu<ChatContextAction>(
    context: context,
    position: position,
    items: [
      if (ChatContextAction.open.enabled(room: room, space: space))
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
      if (enabledCount > 1) const PopupMenuDivider(),
      if (ChatContextAction.goToSpace.enabled(room: room, space: space))
        PopupMenuItem(
          value: ChatContextAction.goToSpace,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(
                mxContent: space!.avatar,
                size: Avatar.defaultSize / 2,
                name: space.getLocalizedDisplayname(),
                userId: space.directChatMatrixID,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l10n.goToCourse(space.getLocalizedDisplayname())),
              ),
            ],
          ),
        ),
      if (ChatContextAction.mute.enabled(room: room, space: space))
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
      if (ChatContextAction.markUnread.enabled(room: room, space: space))
        PopupMenuItem(
          value: ChatContextAction.markUnread,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                room.markedUnread
                    ? Icons.mark_as_unread
                    : Icons.mark_as_unread_outlined,
              ),
              const SizedBox(width: 12),
              Text(room.markedUnread ? l10n.markAsRead : l10n.markAsUnread),
            ],
          ),
        ),
      if (ChatContextAction.favorite.enabled(room: room, space: space))
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
      if (ChatContextAction.endActivity.enabled(room: room, space: space))
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
      if (ChatContextAction.leave.enabled(room: room, space: space))
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
      if (ChatContextAction.delete.enabled(room: room, space: space))
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
    ],
  );

  if (action == null) return;

  switch (action) {
    case ChatContextAction.open:
      onChatTap.call();
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
      await showFutureLoadingDialog(
        context: context,
        future: () => room.markUnread(!room.markedUnread),
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
      if (confirmed != OkCancelResult.ok) return;

      final isSpace = room.isSpace;
      final resp = await showFutureLoadingDialog(
        context: outerContext,
        future: isSpace ? room.leaveSpace : room.leave,
      );

      final r = room.client.getRoomById(room.id);
      if (r != null && r.membership != Membership.leave) {
        await room.client.waitForRoomInSync(room.id, leave: true);
      }

      if (!resp.isError) {
        isSpace
            ? context.go(PRoutes.chatsList)
            : closeRoomPanelFromList(outerContext, room.id);
      }

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
        if (confirmed != OkCancelResult.ok) return;
        final resp = await showFutureLoadingDialog(
          context: outerContext,
          future: room.delete,
        );
        if (!resp.isError) {
          closeRoomPanelFromList(outerContext, room.id);
        }
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
