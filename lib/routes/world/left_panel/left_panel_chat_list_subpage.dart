import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/world/panel_header.dart';

class LeftPanelChatListSubpage extends StatefulWidget {
  final Widget closeButton;

  const LeftPanelChatListSubpage({super.key, required this.closeButton});

  @override
  State<LeftPanelChatListSubpage> createState() =>
      _LeftPanelChatListSubpageState();
}

class _LeftPanelChatListSubpageState extends State<LeftPanelChatListSubpage> {
  /// Whether the search field row is shown below the header. Off by default:
  /// vertical space is the sheet's scarce resource and searching a chat list
  /// is uncommon, so search lives as a header icon that expands on demand
  /// (routing.instructions.md → Single-column bottom nav).
  final ValueNotifier<bool> _searchVisible = ValueNotifier(false);

  @override
  void dispose() {
    _searchVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // The chat list has no header of its own; give the panel a "Chats"
    // title + close control at the top, matching the right column's card
    // chrome. The X dismisses the list to the map (← when it folds over a
    // sibling on narrow). Trailing: the expanding search toggle and the
    // new-chat action (the old floating Direct Message FAB, moved here so it
    // no longer covers list rows). See routing.instructions.md.
    return Column(
      children: [
        PanelHeader(
          leading: widget.closeButton,
          title: l10n.chats,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _searchVisible,
                builder: (context, searching, _) => IconButton(
                  tooltip: l10n.search,
                  isSelected: searching,
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () => _searchVisible.value = !searching,
                ),
              ),
              IconButton(
                tooltip: l10n.directMessage,
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: () => context.go(
                  WorkspaceNav.openLeft(
                    GoRouterState.of(context).uri,
                    NewPrivateChatPanelToken(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ChatList(
            activeChat: activeRoomIdFor(GoRouterState.of(context)),
            activeSpace: null,
            searchFieldVisibility: _searchVisible,
          ),
        ),
      ],
    );
  }
}
