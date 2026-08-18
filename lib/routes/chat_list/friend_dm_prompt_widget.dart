import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/friend_dm_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The chat list's nudge to reach out to a friend (#8395): the Pangea
/// characters waving over an "Invite a friend" button that opens the New
/// direct message panel — the same new-chat action the panel header carries.
/// Shown while the learner has no DM with another person (a bot or support DM
/// doesn't count), whatever other rooms they're in; gone once they do.
class FriendDMPrompt extends StatelessWidget {
  /// Hidden while the list is in search mode, like the bot and support tiles.
  final bool visible;

  const FriendDMPrompt({super.key, this.visible = true});

  static const double _padding = 16.0;
  static const double _illustrationHeight = 150.0;
  static const double _illustrationButtonGap = 8.0;
  static const double _buttonHeight = 40.0;

  /// The prompt's full height, for the mobile chats sheet's content-fit
  /// estimate (workspace_shell): the sheet opens tall enough to show the prompt
  /// below the chat rows instead of leaving it to be found by dragging.
  static const double estimatedHeight =
      _padding * 2 +
      _illustrationHeight +
      _illustrationButtonGap +
      _buttonHeight;

  @override
  Widget build(BuildContext context) {
    if (!visible || Matrix.of(context).client.hasFriendDM) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(_padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/pangea/character_group.png',
            height: _illustrationHeight,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: _illustrationButtonGap),
          SizedBox(
            width: double.infinity,
            height: _buttonHeight,
            child: FilledButton.tonalIcon(
              onPressed: () => context.go(
                WorkspaceNav.openLeft(
                  GoRouterState.of(context).uri,
                  NewPrivateChatPanelToken(),
                ),
              ),
              icon: Icon(Icons.adaptive.share_outlined, size: 20.0),
              label: Text(L10n.of(context).inviteAFriend),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
