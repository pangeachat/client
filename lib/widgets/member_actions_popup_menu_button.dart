import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/level_display_name.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/permission_slider_dialog.dart';
import 'adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'adaptive_dialogs/user_dialog.dart';
import 'future_loading_dialog.dart';

void showMemberActionsPopupMenu({
  required BuildContext context,
  required User user,
  void Function()? onMention,
}) async {
  final theme = Theme.of(context);
  final displayname = user.calcDisplayname();
  // #Pangea
  // final isMe = user.room.client.userID == user.id;
  final dmRoomId = user.room.client.getDirectChatFromUserId(user.id);
  // Pangea#

  // #Pangea
  // final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context, rootOverlay: true)
      .context
      .findRenderObject() as RenderBox;
  // Pangea#

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

  final action = await showMenu<_MemberActions>(
    // #Pangea
    useRootNavigator: true,
    // Pangea#
    context: context,
    position: position,
    items: <PopupMenuEntry<_MemberActions>>[
      PopupMenuItem(
        value: _MemberActions.info,
        child: Row(
          spacing: 12.0,
          children: [
            Avatar(
              name: displayname,
              mxContent: user.avatarUrl,
              presenceUserId: user.id,
              presenceBackgroundColor: theme.colorScheme.surfaceContainer,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 128),
                  child: Text(
                    displayname,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 128),
                  child: Text(
                    user.id,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // #Pangea
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LevelDisplayName(userId: user.id),
                    ],
                  ),
                ),
                // Pangea#
              ],
            ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      // #Pangea
      if (user.room.client.userID != user.id)
        PopupMenuItem(
          value: _MemberActions.chat,
          child: Row(
            children: [
              const Icon(Icons.forum_outlined),
              const SizedBox(width: 18),
              Text(
                dmRoomId == null
                    ? L10n.of(context).startConversation
                    : L10n.of(context).sendAMessage,
              ),
            ],
          ),
        ),
      // Pangea#
      if (onMention != null)
        PopupMenuItem(
          value: _MemberActions.mention,
          child: Row(
            children: [
              const Icon(Icons.alternate_email_outlined),
              const SizedBox(width: 18),
              Text(L10n.of(context).mention),
            ],
          ),
        ),
      if (user.membership == Membership.knock)
        PopupMenuItem(
          value: _MemberActions.approve,
          child: Row(
            children: [
              const Icon(Icons.how_to_reg_outlined),
              const SizedBox(width: 18),
              Text(L10n.of(context).approve),
            ],
          ),
        ),
      PopupMenuItem(
        enabled: user.room.canChangePowerLevel && user.canChangeUserPowerLevel,
        value: _MemberActions.setRole,
        child: Row(
          children: [
            const Icon(Icons.admin_panel_settings_outlined),
            const SizedBox(width: 18),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L10n.of(context).chatPermissions),
                Text(
                  user.powerLevel < 50
                      ? L10n.of(context).userLevel(user.powerLevel)
                      : user.powerLevel < 100
                          ? L10n.of(context).moderatorLevel(user.powerLevel)
                          : L10n.of(context).adminLevel(user.powerLevel),
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      if (user.canKick)
        PopupMenuItem(
          value: _MemberActions.kick,
          child: Row(
            children: [
              Icon(
                Icons.person_remove_outlined,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 18),
              Text(
                L10n.of(context).kickFromChat,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ],
          ),
        ),
      if (user.canBan && user.membership != Membership.ban)
        PopupMenuItem(
          value: _MemberActions.ban,
          child: Row(
            children: [
              Icon(
                Icons.block_outlined,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 18),
              Text(
                L10n.of(context).banFromChat,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ],
          ),
        ),
      if (user.canBan && user.membership == Membership.ban)
        PopupMenuItem(
          value: _MemberActions.unban,
          child: Row(
            children: [
              const Icon(Icons.warning),
              const SizedBox(width: 18),
              Text(L10n.of(context).unbanFromChat),
            ],
          ),
        ),
      // #Pangea
      // if (!isMe)
      //   PopupMenuItem(
      //     value: _MemberActions.report,
      //     child: Row(
      //       children: [
      //         Icon(
      //           Icons.gavel_outlined,
      //           color: theme.colorScheme.onErrorContainer,
      //         ),
      //         const SizedBox(width: 18),
      //         Text(
      //           L10n.of(context).reportUser,
      //           style: TextStyle(color: theme.colorScheme.onErrorContainer),
      //         ),
      //       ],
      //     ),
      //   ),
      // Pangea#
    ],
  );
  if (action == null) return;
  if (!context.mounted) return;

  switch (action) {
    case _MemberActions.mention:
      onMention?.call();
      return;
    case _MemberActions.setRole:
      final power = await showPermissionChooser(
        context,
        currentLevel: user.powerLevel,
        maxLevel: user.room.ownPowerLevel,
      );
      if (power == null) return;
      if (!context.mounted) return;
      if (power >= 100) {
        final consent = await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context).areYouSure,
          message: L10n.of(context).makeAdminDescription,
        );
        if (consent != OkCancelResult.ok) return;
        if (!context.mounted) return;
      }
      await showFutureLoadingDialog(
        context: context,
        future: () => user.setPower(power),
      );
      return;
    case _MemberActions.approve:
      await showFutureLoadingDialog(
        context: context,
        future: () => user.room.invite(user.id),
      );
      return;
    case _MemberActions.kick:
      if (await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).areYouSure,
            okLabel: L10n.of(context).yes,
            cancelLabel: L10n.of(context).no,
            // #Pangea
            // message: L10n.of(context).kickUserDescription,
            message: user.id == BotName.byEnvironment &&
                    !user.room.isSpace &&
                    !user.room.isDirectChat
                ? L10n.of(context).kickBotWarning
                : L10n.of(context).kickUserDescription,
            // Pangea#
          ) ==
          OkCancelResult.ok) {
        await showFutureLoadingDialog(
          context: context,
          future: () => user.kick(),
        );
      }
      return;
    case _MemberActions.ban:
      if (await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).areYouSure,
            okLabel: L10n.of(context).yes,
            cancelLabel: L10n.of(context).no,
            message: L10n.of(context).banUserDescription,
          ) ==
          OkCancelResult.ok) {
        await showFutureLoadingDialog(
          context: context,
          future: () => user.ban(),
        );
      }
      return;
    // #Pangea
    // case _MemberActions.report:
    //   final reason = await showTextInputDialog(
    //     context: context,
    //     title: L10n.of(context).whyDoYouWantToReportThis,
    //     okLabel: L10n.of(context).report,
    //     cancelLabel: L10n.of(context).cancel,
    //     hintText: L10n.of(context).reason,
    //   );
    //   if (reason == null || reason.isEmpty) return;

    //   final result = await showFutureLoadingDialog(
    //     context: context,
    //     future: () => user.room.client.reportUser(
    //       user.id,
    //       reason,
    //     ),
    //   );
    //   if (result.error != null) return;
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(content: Text(L10n.of(context).contentHasBeenReported)),
    //   );
    //   return;
    case _MemberActions.chat:
      final router = GoRouter.of(context);
      final roomIdResult = await showFutureLoadingDialog(
        context: context,
        future: () => user.room.client.startDirectChat(
          user.id,
          enableEncryption: false,
        ),
      );
      Navigator.of(context).pop();
      final roomId = roomIdResult.result;
      if (roomId == null) return;
      router.go('/rooms/$roomId');
    // Pangea#
    case _MemberActions.info:
      await UserDialog.show(
        context: context,
        profile: Profile(
          userId: user.id,
          displayName: user.displayName,
          avatarUrl: user.avatarUrl,
        ),
      );
      return;
    case _MemberActions.unban:
      if (await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context).areYouSure,
            okLabel: L10n.of(context).yes,
            cancelLabel: L10n.of(context).no,
            message: L10n.of(context).unbanUserDescription,
          ) ==
          OkCancelResult.ok) {
        await showFutureLoadingDialog(
          context: context,
          future: () => user.unban(),
        );
      }
  }
}

enum _MemberActions {
  info,
  mention,
  setRole,
  kick,
  ban,
  approve,
  unban,
  // #Pangea
  // report,
  chat,
  // Pangea#
}
