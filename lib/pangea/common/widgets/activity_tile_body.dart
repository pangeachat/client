import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// The body of a live (**ongoing-active**) activity session: the last chat
/// event with its sender's avatar. No goal row (#9559): goals live in the
/// session's own goal header, and an activity's tile and card speak in XP.
/// Shared by the world map's ongoing-active large card and that same session's
/// Chats-list tile, so the two cannot drift (world-map.instructions.md, "Pin
/// display").
///
/// [preview] is the host's own last-event text — the two resolve it
/// differently. Left null, this computes the SDK fallback, which is the map's
/// case.
class ActivityTileBody extends StatelessWidget {
  /// Null while a card has no room yet: the preview row is then dropped.
  final Room? room;

  final Widget? preview;

  final double avatarSize;

  const ActivityTileBody({
    super.key,
    required this.room,
    this.preview,
    this.avatarSize = 24,
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

    if (previewChild == null) return const SizedBox.shrink();
    return Semantics(
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
    );
  }
}
