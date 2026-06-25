import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';
import 'package:fluffychat/routes/world/panel_header.dart';

class LeftPanelChatListSubpage extends StatelessWidget {
  final PanelToken token;
  final Uri currentUri;
  final bool foldedOver;
  final bool isColumnMode;

  const LeftPanelChatListSubpage({
    super.key,
    required this.token,
    required this.currentUri,
    required this.foldedOver,
    required this.isColumnMode,
  });

  @override
  Widget build(BuildContext context) {
    // The chat list has no header of its own; give the panel a "Chats"
    // title + close control at the top, matching the right column's card
    // chrome. The X dismisses the list to the map (← when it folds over a
    // sibling on narrow). See routing.instructions.md.
    return Column(
      children: [
        PanelHeader(
          leading: LeftPanelCloseButton(
            token: token,
            currentUri: currentUri,
            foldedOver: foldedOver,
            isColumnMode: isColumnMode,
          ),
          title: L10n.of(context).chats,
        ),
        Expanded(
          child: ChatList(
            activeChat: activeRoomIdFor(GoRouterState.of(context)),
            activeSpace: null,
          ),
        ),
      ],
    );
  }
}
