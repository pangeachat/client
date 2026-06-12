import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_room_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class DeleteSpaceDialog extends StatefulWidget {
  final List<SpaceRoomsChunk$2> roomsChunks;
  const DeleteSpaceDialog({super.key, required this.roomsChunks});

  static Future<void> show(Room room, BuildContext context) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: room.spaceChildCount > 0
          ? L10n.of(context).deleteSpaceDesc
          : L10n.of(context).deleteEmptySpaceDesc,
      isDestructive: true,
    );

    if (response != OkCancelResult.ok) return;

    final resp = await showFutureLoadingDialog<List<SpaceRoomsChunk$2>>(
      context: context,
      future: room.getSpaceChildrenToDelete,
    );
    final roomChunks = resp.result;
    if (roomChunks == null) return;

    List<String>? deleteRoomIds;
    if (roomChunks.isNotEmpty) {
      final deleteRoomIds = await showDialog<List<String>?>(
        context: context,
        builder: (_) => DeleteSpaceDialog(roomsChunks: roomChunks),
      );
      if (deleteRoomIds == null) return;
    }

    final result = await showFutureLoadingDialog(
      context: context,
      future: () => room.deleteSpace(deleteRoomIds ?? []),
    );

    if (!result.isError) {
      context.go("/rooms");
    }
  }

  @override
  State<DeleteSpaceDialog> createState() => DeleteSpaceDialogState();
}

class DeleteSpaceDialogState extends State<DeleteSpaceDialog> {
  final List<SpaceRoomsChunk$2> _roomsToDelete = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<SpaceRoomsChunk$2> get _selectableRooms {
    return widget.roomsChunks.where((chunk) {
      final room = Matrix.of(context).client.getRoomById(chunk.roomId);
      return room != null &&
          room.membership == Membership.join &&
          room.isRoomAdmin;
    }).toList();
  }

  List<String> get _selectedRoomIds =>
      _roomsToDelete.map((r) => r.roomId).toList();

  void _onRoomSelected(bool? selected, SpaceRoomsChunk$2 room) {
    if (selected == null ||
        (selected && _roomsToDelete.contains(room)) ||
        (!selected && !_roomsToDelete.contains(room))) {
      return;
    }

    setState(() {
      selected ? _roomsToDelete.add(room) : _roomsToDelete.remove(room);
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_roomsToDelete.length == _selectableRooms.length) {
        _roomsToDelete.clear();
      } else {
        _roomsToDelete
          ..clear()
          ..addAll(_selectableRooms);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final selectableRooms = _selectableRooms;
    return AlertDialog.adaptive(
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Text(L10n.of(context).selectChats),
      ),
      content: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 256, maxHeight: 400),
          child: widget.roomsChunks.isNotEmpty
              ? Column(
                  spacing: 8.0,
                  children: [
                    SizedBox(),
                    if (selectableRooms.length > 1) ...[
                      Row(
                        children: [
                          Checkbox(
                            value:
                                _roomsToDelete.length == selectableRooms.length,
                            onChanged: (_) => _toggleSelectAll(),
                          ),
                          Expanded(
                            child: Text(
                              _roomsToDelete.length == selectableRooms.length
                                  ? L10n.of(context).deselectAll
                                  : L10n.of(context).selectAll,
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 1),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          spacing: 8.0,
                          children: [
                            ...widget.roomsChunks.map((chunk) {
                              final room = client.getRoomById(chunk.roomId);
                              final isMember =
                                  room != null &&
                                  room.membership == Membership.join &&
                                  room.isRoomAdmin;

                              final displayname =
                                  chunk.name ??
                                  chunk.canonicalAlias ??
                                  L10n.of(context).emptyChat;

                              return AnimatedOpacity(
                                duration: FluffyThemes.animationDuration,
                                opacity: isMember ? 1 : 0.5,
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: _roomsToDelete.contains(chunk),
                                      onChanged: isMember
                                          ? (value) =>
                                                _onRoomSelected(value, chunk)
                                          : null,
                                    ),
                                    Expanded(child: Text(displayname)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : SizedBox(),
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).cancel),
        ),
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(_selectedRoomIds),
          autofocus: true,
          child: Text(
            L10n.of(context).delete,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}
