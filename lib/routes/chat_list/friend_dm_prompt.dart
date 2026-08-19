import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The chat list's nudge to reach out to a friend (#8395): the Pangea cast
/// waving over an "Invite a friend" button that opens the New direct message
/// panel — the same new-chat action the panel header carries. The list mounts
/// it while the learner has no [FriendDMRoomExtension.isFriendDM].
class FriendDMPrompt extends StatelessWidget {
  const FriendDMPrompt({super.key});

  /// The cast illustration, hosted in the client assets bucket rather than
  /// bundled like the rest of the artwork so a redraw needs no app release.
  static const String _illustration = 'Group_Of_Five.png';

  static const double _padding = 16.0;

  /// The artwork's box, not the cast: it is drawn across the bottom two thirds
  /// of a transparent canvas, so the empty band above becomes the gap up to
  /// the last chat row and the narrow one below lets the button overlap the
  /// cast's feet, standing them behind it the way the mockup does.
  static const double _illustrationHeight = 240.0;

  /// What the mobile chats sheet's content-fit estimate adds for the prompt,
  /// so it opens showing the button instead of leaving it behind a drag.
  static const double estimatedHeight = _illustrationHeight + _padding * 2;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(_padding),
    child: Stack(
      alignment: Alignment.bottomCenter,
      children: [
        ExcludeSemantics(
          child: CachedNetworkImage(
            imageUrl: '${AppConfig.assetsBaseURL}/$_illustration',
            // The height is reserved whatever the fetch does, so the list
            // doesn't jump when the artwork arrives and the sheet estimate
            // above holds either way. A stale or unreachable bucket then
            // leaves empty space rather than a broken-image box, and the
            // button alone still makes the point.
            height: _illustrationHeight,
            fit: BoxFit.contain,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            icon: Icon(Icons.adaptive.share_outlined, size: 20.0),
            label: Text(L10n.of(context).inviteAFriend),
            onPressed: () => context.go(
              WorkspaceNav.openLeft(
                GoRouterState.of(context).uri,
                const NewPrivateChatPanelToken(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
