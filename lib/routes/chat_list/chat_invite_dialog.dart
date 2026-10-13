import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/invite_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

enum InviteAction { accept, decline, block }

/// The accept / decline / block prompt for an invite to a chat, shared by the
/// chat list, a course's chat list and a tapped notification. A course invite
/// has its own prompt, [RoomInviteDialog].
class ChatInviteDialog {
  /// Resolves the invite to [room] and returns whether the user is now in it,
  /// so the caller can open it. An invite the user knocked for is joined
  /// without asking (joining-courses.instructions.md, KnockTracker).
  static Future<bool> show(BuildContext context, Room room) async {
    if (room.hasKnocked) return _join(context, room);

    final l10n = L10n.of(context);
    final matrixLocals = MatrixLocals(l10n);
    final inviteEvent = room.getState(
      EventTypes.RoomMember,
      room.client.userID!,
    );
    final action = await showInviteDialog<InviteAction>(
      context,
      title: room.getLocalizedDisplayname(matrixLocals),
      message: inviteEvent == null
          ? l10n.inviteForMe
          : inviteEvent.content.tryGet<String>('reason') ??
                l10n.youInvitedBy(
                  room
                      .unsafeGetUserFromMemoryOrFallback(inviteEvent.senderId)
                      .calcDisplayname(i18n: matrixLocals),
                ),
      actions: [
        InviteDialogAction(label: l10n.accept, value: InviteAction.accept),
        InviteDialogAction(
          label: l10n.decline,
          value: InviteAction.decline,
          destructive: true,
        ),
        InviteDialogAction(
          label: l10n.block,
          value: InviteAction.block,
          destructive: true,
        ),
      ],
    );
    if (!context.mounted) return false;

    switch (action) {
      case null:
        return false;
      case InviteAction.accept:
        return _join(context, room);
      case InviteAction.decline:
        await showFutureLoadingDialog(context: context, future: room.leave);
        return false;
      case InviteAction.block:
        // Read the URI from the router: a notification tap prompts from the
        // root navigator's context, which has no GoRouterState above it.
        final router = GoRouter.of(context);
        final userId = inviteEvent?.senderId;
        router.go(
          WorkspaceNav.openSettings(
            router.routeInformationProvider.value.uri,
            page: userId == null
                ? 'security/ignorelist'
                : 'security/ignorelist/$userId',
          ),
        );
        return false;
    }
  }

  static Future<bool> _join(BuildContext context, Room room) async {
    final knocked = room.hasKnocked;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final waitForRoom = room.client.waitForRoomInSync(room.id, join: true);
        if (knocked) {
          // joinKnockedRoom reports its own failure and returns null; there is
          // then no join for the sync to bring back.
          if (await room.joinKnockedRoom() == null) return false;
        } else {
          await room.join();
        }
        await waitForRoom;
        return true;
      },
      exceptionContext: ExceptionContext.joinRoom,
    );
    return result.result == true;
  }
}
