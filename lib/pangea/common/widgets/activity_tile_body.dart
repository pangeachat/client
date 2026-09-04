import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// The body of a live (**ongoing-active**) activity session: the last chat
/// event with its sender's avatar, then the row of stars earned so far. Shared
/// by the world map's ongoing-active large card and that same session's
/// Chats-list tile, so the two cannot drift (world-map.instructions.md, "Pin
/// display").
///
/// [preview] is the host's own last-event text — the two resolve it
/// differently. Left null, this computes the SDK fallback, which is the map's
/// case.
class ActivityTileBody extends StatelessWidget {
  /// Null while a card has no room yet: the preview row is then dropped and
  /// only the star row remains.
  final Room? room;

  final Widget? preview;

  final int starsTotal;
  final int starsEarned;

  final double avatarSize;

  /// Icon size for the stars, and the height reserved for their row.
  final double starIconSize;

  final double spacing;

  /// Whether the star row holds its height even with no stars to draw. True on
  /// the map, where the total arrives from a hydrating plan and an unreserved
  /// row would make the card jump 0 → N goals. False on the chat list, which
  /// reads its total from room state and would otherwise hold an empty band
  /// under every tile.
  final bool reserveStarSpace;

  const ActivityTileBody({
    super.key,
    required this.room,
    required this.starsTotal,
    required this.starsEarned,
    this.preview,
    this.avatarSize = 24,
    this.starIconSize = 16,
    this.spacing = 8.0,
    this.reserveStarSpace = true,
  });

  @override
  Widget build(BuildContext context) {
    final lastEvent = room?.lastEvent;
    final sender = lastEvent?.senderFromMemoryOrFallback;

    final fallback = preview != null
        ? null
        : lastEvent?.calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            hideReply: true,
            hideEdit: true,
            plaintextBody: true,
            removeMarkdown: true,
            withSenderNamePrefix: false,
          );
    final previewChild =
        preview ??
        (fallback == null
            ? null
            : Text(
                fallback,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: spacing,
      children: [
        if (previewChild != null)
          Semantics(
            label: L10n.of(context).activityPreviewLabel,
            container: true,
            child: Row(
              children: [
                Avatar(
                  mxContent: sender?.avatarUrl,
                  name: sender?.localizedDisplayname(L10n.of(context)),
                  size: avatarSize,
                ),
                const SizedBox(width: 8),
                Expanded(child: previewChild),
              ],
            ),
          ),
        if (starsTotal > 0 || reserveStarSpace)
          Semantics(
            container: true,
            child: SizedBox(
              height: starIconSize,
              child: ActivityStarRow(
                total: starsTotal,
                earned: starsEarned.clamp(0, starsTotal),
                iconSize: starIconSize,
                condensed: starsTotal > 12,
              ),
            ),
          ),
      ],
    );
  }
}
