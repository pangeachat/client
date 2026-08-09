import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/bot/widgets/bot_chat_settings_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/users/about_me_display.dart';
import 'package:fluffychat/widgets/users/level_display_name.dart';
import 'package:fluffychat/widgets/users/member_actions.dart';

RelativeRect _position(BuildContext positionContext) {
  final overlay =
      Overlay.of(positionContext).context.findRenderObject() as RenderBox;
  final button = positionContext.findRenderObject() as RenderBox;
  return RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(const Offset(0, -65), ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero) + const Offset(-50, 0),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );
}

Future<MemberAction?> _getAction(
  BuildContext context, {
  BuildContext? positionContext,
  required User user,
  Room? room,
  VoidCallback? onMention,
}) {
  final theme = Theme.of(context);
  final l10n = L10n.of(context);

  PopupMenuItem<MemberAction> actionPopupMenuItem(MemberAction action) =>
      PopupMenuItem<MemberAction>(
        value: action,
        child: Row(
          children: [
            Icon(action.icon, color: action.iconColor(theme)),
            const SizedBox(width: 18),
            Text(action.text(l10n), style: action.textStyle(theme)),
          ],
        ),
      );

  final popupContext = positionContext ?? context;
  final position = _position(popupContext);

  final displayname = user.localizedDisplayname(l10n);
  final dmRoomId = user.room.client.getDirectChatFromUserId(user.id);
  final isBotInActivity =
      user.id == BotName.byEnvironment && room?.showActivityChatUI == true;

  final infoAction = InfoMemberAction(user: user);
  final chatAction = ChatMemberAction(user: user, dmRoomId: dmRoomId);
  final mentionAction = MentionMemberAction(onMention: onMention);
  final approveAction = ApproveMemberAction(user: user);
  final kickAction = KickMemberAction(
    user: user,
    isBotInActivity: isBotInActivity,
  );
  final setRoleAction = SetRoleMemberAction(user: user);
  final banAction = BanMemberAction(
    user: user,
    isBotInActivity: isBotInActivity,
  );
  final unbanAction = UnbanMemberAction(user: user);

  return showMenu<MemberAction>(
    context: context,
    position: position,
    items: <PopupMenuEntry<MemberAction>>[
      if (infoAction.visible())
        PopupMenuItem(
          value: infoAction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                      Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [LevelDisplayName(userId: user.id)],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              AboutMeDisplay(userId: user.id),
            ],
          ),
        ),
      if (user.id == BotName.byEnvironment && room != null && room.isRoomAdmin)
        PopupMenuItem(
          enabled: false,
          padding: const EdgeInsets.only(left: 12.0, right: 12.0),
          child: BotChatSettingsDialog(room: room),
        ),
      if (user.room.client.userID != user.id) const PopupMenuDivider(),
      if (chatAction.visible()) actionPopupMenuItem(chatAction),
      if (mentionAction.visible()) actionPopupMenuItem(mentionAction),
      if (approveAction.visible()) actionPopupMenuItem(approveAction),
      if (setRoleAction.visible())
        PopupMenuItem(
          enabled: setRoleAction.enabled(),
          value: setRoleAction,
          child: Row(
            children: [
              Icon(setRoleAction.icon),
              const SizedBox(width: 18),
              Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  Text(setRoleAction.text(l10n)),
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
      if (kickAction.visible()) actionPopupMenuItem(kickAction),
      if (banAction.visible()) actionPopupMenuItem(banAction),
      if (unbanAction.visible()) actionPopupMenuItem(unbanAction),
    ],
  );
}

Future<void> showMemberActionsPopupMenu({
  required BuildContext context,
  BuildContext? positionContext,
  required User user,
  Room? room,
  VoidCallback? onMention,
}) async {
  final action = await _getAction(
    context,
    positionContext: positionContext,
    user: user,
    room: room,
    onMention: onMention,
  );
  if (action == null || !context.mounted) return;
  await action.execute(context);
}
