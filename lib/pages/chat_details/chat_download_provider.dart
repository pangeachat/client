import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/download/download_room_extension.dart';
import 'package:fluffychat/pangea/download/download_type_enum.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin ChatDownloadProvider {
  void downloadChatAction(String roomId, BuildContext context) async {
    final Room? room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null) return;

    final type = await showModalActionPopup(
      context: context,
      title: L10n.of(context).downloadGroupText,
      actions: [
        AdaptiveModalAction(
          value: DownloadType.csv,
          label: L10n.of(context).downloadCSVFile,
        ),
        AdaptiveModalAction(
          value: DownloadType.txt,
          label: L10n.of(context).downloadTxtFile,
        ),
        AdaptiveModalAction(
          value: DownloadType.xlsx,
          label: L10n.of(context).downloadXLSXFile,
        ),
      ],
    );
    if (type == null) return;

    try {
      await room.download(type, context);
    } on EmptyChatException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).emptyChatDownloadWarning)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${L10n.of(context).oopsSomethingWentWrong} ${L10n.of(context).errorPleaseRefresh}",
          ),
        ),
      );
    }
  }
}
