import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/permission_slider_dialog.dart';

sealed class MemberAction {
  const MemberAction();

  IconData get icon;

  Color? iconColor(ThemeData theme) => null;

  String text(L10n l10n);

  TextStyle? textStyle(ThemeData theme) => null;

  bool visible() => true;

  bool enabled() => true;

  Future<void> execute(BuildContext context);
}

class InfoMemberAction extends MemberAction {
  final User user;
  const InfoMemberAction({required this.user});

  @override
  IconData get icon => Icons.info_outline;

  @override
  String text(L10n l10n) => l10n.profile;

  @override
  Future<void> execute(BuildContext context) => UserDialog.show(
    context: context,
    profile: Profile(
      userId: user.id,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
    ),
    uri: GoRouterState.of(context).uri,
  );
}

class MentionMemberAction extends MemberAction {
  final VoidCallback? onMention;
  const MentionMemberAction({required this.onMention});

  @override
  IconData get icon => Icons.alternate_email_outlined;

  @override
  String text(L10n l10n) => l10n.mention;

  @override
  bool visible() => onMention != null;

  @override
  Future<void> execute(BuildContext _) async => onMention?.call();
}

class SetRoleMemberAction extends MemberAction {
  final User user;
  const SetRoleMemberAction({required this.user});

  @override
  IconData get icon => Icons.admin_panel_settings_outlined;

  @override
  String text(L10n l10n) =>
      user.room.isSpace ? l10n.coursePermissions : l10n.chatPermissions;

  @override
  bool visible() =>
      user.room.canChangePowerLevel && user.canChangeUserPowerLevel;

  @override
  bool enabled() =>
      user.room.canChangePowerLevel && user.canChangeUserPowerLevel;

  @override
  Future<void> execute(BuildContext context) async {
    final power = await showPermissionChooser(
      context,
      currentLevel: user.powerLevel,
      maxLevel: user.room.ownPowerLevel,
      isCourse: user.room.isSpace,
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
    if (power < 100 && user.powerLevel >= 100) {
      // If the user is already admin, we are demoting them, so we want to show a different message and get different consent
      final consent = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).areYouSure,
        message: L10n.of(context).removeAdminDescription,
      );
      if (consent != OkCancelResult.ok) return;
      if (!context.mounted) return;
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => user.setPower(power),
    );
  }
}

class KickMemberAction extends MemberAction {
  final User user;
  final bool isBotInActivity;
  const KickMemberAction({required this.user, required this.isBotInActivity});

  bool get _canKickNonKnockingUser =>
      user.canKick && user.membership != Membership.knock && !isBotInActivity;

  bool get _canKickKnockingUser =>
      user.canKick && user.membership == Membership.knock;

  @override
  IconData get icon => Icons.person_remove_outlined;

  @override
  String text(L10n l10n) =>
      user.membership == Membership.knock ? l10n.deny : l10n.kick;

  @override
  TextStyle? textStyle(ThemeData theme) => user.membership != Membership.knock
      ? TextStyle(color: theme.colorScheme.onErrorContainer)
      : null;

  @override
  bool visible() => _canKickKnockingUser || _canKickNonKnockingUser;

  @override
  Future<void> execute(BuildContext context) async {
    if (await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context).areYouSure,
          okLabel: L10n.of(context).yes,
          cancelLabel: L10n.of(context).no,
          message:
              user.id == BotName.byEnvironment &&
                  !user.room.isSpace &&
                  !user.room.isDirectChat
              ? L10n.of(context).kickBotWarning
              : user.membership == Membership.knock
              ? user.room.isSpace
                    ? L10n.of(context).denyKnockSpace
                    : L10n.of(context).denyKnockChat
              : L10n.of(context).kickUserDescription,
        ) ==
        OkCancelResult.ok) {
      await showFutureLoadingDialog(
        context: context,
        future: () => user.kick(),
      );
    }
  }
}

class BanMemberAction extends MemberAction {
  final User user;
  final bool isBotInActivity;
  const BanMemberAction({required this.user, required this.isBotInActivity});

  @override
  IconData get icon => Icons.block_outlined;

  @override
  Color iconColor(ThemeData theme) => theme.colorScheme.onErrorContainer;

  @override
  String text(L10n l10n) => user.room.isSpace ? l10n.banFromSpace : l10n.ban;

  @override
  TextStyle textStyle(ThemeData theme) =>
      TextStyle(color: theme.colorScheme.onErrorContainer);

  @override
  bool visible() =>
      user.canBan && user.membership != Membership.ban && !isBotInActivity;

  @override
  Future<void> execute(BuildContext context) async {
    if (await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context).areYouSure,
          okLabel: L10n.of(context).yes,
          cancelLabel: L10n.of(context).no,
          message: L10n.of(context).banUserDescription,
        ) ==
        OkCancelResult.ok) {
      await showFutureLoadingDialog(context: context, future: () => user.ban());
    }
  }
}

class ApproveMemberAction extends MemberAction {
  final User user;
  const ApproveMemberAction({required this.user});

  @override
  IconData get icon => Icons.how_to_reg_outlined;

  @override
  String text(L10n l10n) => l10n.approve;

  @override
  // Accepting a knock issues an invite, so the action needs the viewer to
  // hold the room's invite power — without it the approval can only fail
  // with M_FORBIDDEN (#8694).
  bool visible() => user.membership == Membership.knock && user.room.canInvite;

  @override
  Future<void> execute(BuildContext context) => showFutureLoadingDialog(
    context: context,
    future: () => user.room.acceptKnock(user.id),
  );
}

class UnbanMemberAction extends MemberAction {
  final User user;
  const UnbanMemberAction({required this.user});

  @override
  IconData get icon => Icons.warning;

  @override
  String text(L10n l10n) =>
      user.room.isSpace ? l10n.unbanFromSpace : l10n.unbanFromChat;

  @override
  bool visible() => user.canBan && user.membership == Membership.ban;

  @override
  Future<void> execute(BuildContext context) async {
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

class ChatMemberAction extends MemberAction {
  final User user;
  final String? dmRoomId;
  const ChatMemberAction({required this.user, required this.dmRoomId});

  @override
  IconData get icon => Icons.forum_outlined;

  @override
  String text(L10n l10n) =>
      dmRoomId == null ? l10n.startConversation : l10n.sendAMessage;

  @override
  bool visible() => user.room.client.userID != user.id;

  @override
  Future<void> execute(BuildContext context) async {
    final router = GoRouter.of(context);
    final roomIdResult = await showFutureLoadingDialog(
      context: context,
      future: () => user.room.client.createPangeaDirectChat(user.id),
    );
    final roomId = roomIdResult.result;
    if (roomId == null) return;
    if (!context.mounted) return;
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    router.go(WorkspaceNav.openRoomById(uri, roomId));
  }
}
