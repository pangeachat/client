import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'matrix.dart';

enum ChatPopupMenuActions { details, mute, unmute, emote, leave, search }

class ChatSettingsPopupMenu extends StatefulWidget {
  final Room room;
  final bool displayChatDetails;

  const ChatSettingsPopupMenu(this.room, this.displayChatDetails, {super.key});

  @override
  ChatSettingsPopupMenuState createState() => ChatSettingsPopupMenuState();
}

class ChatSettingsPopupMenuState extends State<ChatSettingsPopupMenu> {
  StreamSubscription? notificationChangeSub;

  @override
  void dispose() {
    notificationChangeSub?.cancel();
    super.dispose();
  }

  void goToEmoteSettings() => NavigationUtil.goToSpaceRoute(widget.room.id, [
    'details',
    'emotes',
  ], context);

  @override
  Widget build(BuildContext context) {
    notificationChangeSub ??= Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.accountData?.any(
                (accountData) => accountData.type == 'm.push_rules',
              ) ??
              false,
        )
        .listen((u) => setState(() {}));
    return Stack(
      alignment: Alignment.center,
      children: [
        const SizedBox.shrink(),
        PopupMenuButton<ChatPopupMenuActions>(
          useRootNavigator: true,
          onSelected: (choice) async {
            switch (choice) {
              case ChatPopupMenuActions.leave:
                final router = GoRouter.of(context);
                final confirmed = await showOkCancelAlertDialog(
                  context: context,
                  title: L10n.of(context).areYouSure,
                  // #Pangea
                  // message: L10n.of(context).archiveRoomDescription,
                  message: L10n.of(context).leaveRoomDescription,
                  // Pangea#
                  okLabel: L10n.of(context).leave,
                  cancelLabel: L10n.of(context).cancel,
                  isDestructive: true,
                );
                if (confirmed != OkCancelResult.ok) return;
                final result = await showFutureLoadingDialog(
                  context: context,
                  future: () => widget.room.leave(),
                );
                if (result.error == null) {
                  router.go('/rooms');
                }

                break;
              case ChatPopupMenuActions.mute:
                await showFutureLoadingDialog(
                  context: context,
                  future: () =>
                      widget.room.setPushRuleState(PushRuleState.mentionsOnly),
                );
                break;
              case ChatPopupMenuActions.unmute:
                await showFutureLoadingDialog(
                  context: context,
                  future: () =>
                      widget.room.setPushRuleState(PushRuleState.notify),
                );
                break;
              case ChatPopupMenuActions.details:
                _showChatDetails();
                break;
              case ChatPopupMenuActions.search:
                NavigationUtil.goToSpaceRoute(widget.room.id, [
                  'search',
                ], context);
                break;
              case ChatPopupMenuActions.emote:
                goToEmoteSettings();
            }
          },
          itemBuilder: (BuildContext context) => [
            if (widget.displayChatDetails)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.details,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).chatDetails),
                  ],
                ),
              ),
            if (widget.room.pushRuleState == PushRuleState.notify)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.mute,
                child: Row(
                  children: [
                    const Icon(Icons.notifications_off_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).muteChat),
                  ],
                ),
              )
            else
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.unmute,
                child: Row(
                  children: [
                    const Icon(Icons.notifications_on_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).unmuteChat),
                  ],
                ),
              ),
            PopupMenuItem<ChatPopupMenuActions>(
              value: ChatPopupMenuActions.search,
              child: Row(
                children: [
                  const Icon(Icons.search_outlined),
                  const SizedBox(width: 12),
                  Text(L10n.of(context).search),
                ],
              ),
            ),
            PopupMenuItem<ChatPopupMenuActions>(
              value: ChatPopupMenuActions.emote,
              child: Row(
                children: [
                  const Icon(Icons.emoji_emotions_outlined),
                  const SizedBox(width: 12),
                  Text(L10n.of(context).emoteSettings),
                ],
              ),
            ),
            PopupMenuItem<ChatPopupMenuActions>(
              value: ChatPopupMenuActions.leave,
              child: Row(
                children: [
                  const Icon(Icons.delete_outlined),
                  const SizedBox(width: 12),
                  Text(L10n.of(context).leave),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showChatDetails() {
    // world_v2: toggle the room's `details` sub-page. If the live room token is
    // already on `/details`, pop back to the chat; otherwise push details. The
    // path is always `/`, so the state lives in the room token's param. See
    // routing.instructions.md.
    final left = parseOpenPanels(GoRouterState.of(context).uri).left;
    final onDetails = left.any(
      (t) =>
          (t.type == 'room' || t.type == 'session') &&
          (t.param ?? '').split('/').contains('details'),
    );
    NavigationUtil.goToSpaceRoute(
      widget.room.id,
      onDetails ? const [] : const ['details'],
      context,
    );
  }
}
