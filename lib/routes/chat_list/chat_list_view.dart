import 'package:flutter/material.dart';

import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/chat_list/chat_list_view_body_wrapper.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !controller.isSearchMode && controller.activeSpaceId == null,
      onPopInvokedWithResult: (pop, _) {
        if (pop) return;
        if (controller.activeSpaceId != null) {
          controller.clearActiveSpace();
          return;
        }
        if (controller.isSearchMode) {
          controller.cancelSearch();
          return;
        }
      },
      child: Row(
        children: [
          // #Pangea
          // if (FluffyThemes.isColumnMode(context) ||
          //     AppSettings.displayNavigationRail.value) ...[
          //   SpacesNavigationRail(
          //     activeSpaceId: controller.activeSpaceId,
          //     onGoToChats: controller.clearActiveSpace,
          //     onGoToSpaceId: controller.setActiveSpace,
          //   ),
          //   Container(color: Theme.of(context).dividerColor, width: 1),
          // ],
          // Pangea#
          Expanded(
            child: GestureDetector(
              onTap: FocusManager.instance.primaryFocus?.unfocus,
              excludeFromSemantics: true,
              behavior: HitTestBehavior.translucent,
              child: Scaffold(
                // #Pangea
                // body: ChatListViewBody(controller),
                body: ChatListViewBodyWrapper(controller: controller),
                // The Direct Message FAB moved into the panel header as the
                // new-chat action (LeftPanelChatListSubpage) — floating over
                // the list covered its bottom rows in the narrow sheet.
                // Pangea#
              ),
            ),
          ),
        ],
      ),
    );
  }
}
