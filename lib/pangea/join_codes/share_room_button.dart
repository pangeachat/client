import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/join_codes/join_code_room_extension.dart';
import 'package:fluffychat/pangea/join_codes/share_room_code_util.dart';

class ShareRoomButton extends StatelessWidget {
  final Widget child;
  final Room room;
  final String? tooltip;

  const ShareRoomButton({
    super.key,
    required this.child,
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).oopsSomethingWentWrong)),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: toCopy));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.of(context).copiedToClipboard)));
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
      child: child,
      onSelected: (t) => _copyShareCode(context, t),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<ShareCodeType>>[
        PopupMenuItem<ShareCodeType>(
          value: ShareCodeType.link,
          child: ListTile(
            title: Text(L10n.of(context).shareSpaceLink),
            contentPadding: const EdgeInsets.all(0),
          ),
        ),
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
