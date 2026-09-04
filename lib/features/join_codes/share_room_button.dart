import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/join_codes/share_room_code_util.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';

class ShareRoomButton extends StatelessWidget {
  /// The button's glyph, handed to [PopupMenuButton.icon] — which is what
  /// makes this an `IconButton`. The `child` path it used instead wraps the
  /// glyph in a bare rectangular `InkWell` sized to the glyph itself, so the
  /// hover read as a small square hugging the icon's edges while every
  /// IconButton beside it (the course header's focus-on-map) drew a 40px
  /// circle centred in a 48px target. Two buttons in one row cannot disagree
  /// about their own shape (#8816).
  final Widget icon;

  final Room room;
  final String? tooltip;

  const ShareRoomButton({
    super.key,
    required this.icon,
    required this.room,
    this.tooltip,
  });

  Future<void> _copyShareCode(
    BuildContext context,
    ShareCodeType shareType,
  ) async {
    final toCopy = ShareRoomCodeUtil.getRoomCodeToShare(room, shareType);
    if (toCopy == null) {
      ErrorHandler.logError(
        e: "Tried to share a room with no join code",
        data: {
          "roomId": room.id,
          "shareType": shareType.name,
          "roomJoinCode": room.joinCode,
        },
      );

      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(content: Text(L10n.of(context).oopsSomethingWentWrong)),
        assertive: true,
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: toCopy));

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBarAnnounced(
      SnackBar(
        content: Text(L10n.of(context).copiedToClipboard),
        showCloseIcon: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final joinCode = room.joinCode;
    if (joinCode == null) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<ShareCodeType>(
      useRootNavigator: true,
      tooltip: tooltip,
      icon: icon,
      onSelected: (t) => _copyShareCode(context, t),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<ShareCodeType>>[
        PopupMenuItem<ShareCodeType>(
          value: ShareCodeType.link,
          child: ListTile(
            title: Text(L10n.of(context).shareSpaceLink),
            contentPadding: const EdgeInsets.all(0),
          ),
        ),
        // Activity sessions have no code-entry surface to join with, so
        // showing an invite code here would just confuse (#8529).
        if (!room.isActivitySession)
          PopupMenuItem<ShareCodeType>(
            value: ShareCodeType.code,
            child: ListTile(
              title: Text(L10n.of(context).shareInviteCode(joinCode)),
              contentPadding: const EdgeInsets.all(0),
            ),
          ),
      ],
    );
  }
}
