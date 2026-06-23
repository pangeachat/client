import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/download/download_dialog.dart';
import 'package:fluffychat/features/download/download_room_extension.dart';
import 'package:fluffychat/features/download/download_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin ChatDownloadProvider {
  Future<void> downloadChatAction(String roomId, BuildContext context) async {
    final Room? room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null) return;

    await showDialog(
      context: context,
      builder: (context) => ChatDownloadDialog(room: room),
    );
  }
}

class ChatDownloadDialog extends StatefulWidget {
  final Room room;
  const ChatDownloadDialog({required this.room, super.key});

  @override
  ChatDownloadDialogState createState() => ChatDownloadDialogState();
}

class ChatDownloadDialogState extends State<ChatDownloadDialog> {
  bool _downloading = false;
  bool _downloaded = false;
  String? _error;
  DownloadType _downloadType = DownloadType.csv;

  void _setDownloadType(DownloadType type) {
    if (_downloadType == type) return;
    setState(() => _downloadType = type);
  }

  Future<void> _download() async {
    try {
      setState(() {
        _downloading = true;
        _downloaded = false;
        _error = null;
      });
      await widget.room.download(_downloadType, context);
    } on EmptyChatException {
      _error = L10n.of(context).emptyChatDownloadWarning;
    } catch (e) {
      _error = L10n.of(context).errorPleaseRefresh;
    } finally {
      setState(() {
        _downloading = false;
        _downloaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DownloadDialog(
      downloading: _downloading,
      downloaded: _downloaded,
      enableDownload: !_downloading,
      selectedDownloadType: _downloadType,
      downloadableTypes: [
        DownloadType.csv,
        DownloadType.xlsx,
        DownloadType.txt,
      ],
      setDownloadType: _setDownloadType,
      download: _download,
      description: L10n.of(context).chatDownloadDesc,
      error: _error,
    );
  }
}
