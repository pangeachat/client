import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/extensions/pangea_rooms_chunk_extension.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PublicRoomBottomSheet extends StatefulWidget {
  final String? roomAlias;
  final BuildContext outerContext;
  final PublicRoomsChunk? chunk;
  final List<String>? via;

  PublicRoomBottomSheet({
    this.roomAlias,
    required this.outerContext,
    this.chunk,
    this.via,
    super.key,
  }) {
    assert(roomAlias != null || chunk != null);
  }

  static Future<bool?> show({
    required BuildContext context,
    String? roomAlias,
    PublicRoomsChunk? chunk,
    List<String>? via,
  }) async {
    final room = MatrixState.pangeaController.matrixState.client
        .getRoomById(chunk!.roomId);

    if (room != null && room.membership == Membership.join) {
      context.go("/rooms/spaces/${room.id}/details");
      return null;
    }

    return showAdaptiveBottomSheet(
      context: context,
      builder: (context) => PublicRoomBottomSheet(
        roomAlias: roomAlias,
        chunk: chunk,
        via: via,
        outerContext: context,
      ),
    );
  }

  @override
  State<StatefulWidget> createState() => PublicRoomBottomSheetState();
}

class PublicRoomBottomSheetState extends State<PublicRoomBottomSheet> {
  BuildContext get outerContext => widget.outerContext;
  PublicRoomsChunk? get chunk => widget.chunk;
  String? get roomAlias => widget.roomAlias;
  List<String>? get via => widget.via;

  final TextEditingController _codeController = TextEditingController();
  late Client client;

  @override
  void initState() {
    super.initState();
    client = Matrix.of(outerContext).client;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Room? get room => client.getRoomById(chunk!.roomId);
  bool get _isRoomMember => room != null && room!.membership == Membership.join;
  bool get _isKnockRoom => widget.chunk?.joinRule == 'knock';

  Future<void> _joinWithCode() async {
    final resp =
        await MatrixState.pangeaController.classController.joinClasswithCode(
      context,
      _codeController.text,
      notFoundError: L10n.of(context).notTheCodeError,
    );
    if (!resp.isError) {
      Navigator.of(context).pop(true);
    }
  }

  void _goToRoom(String roomID) {
    if (chunk?.roomType != 'm.space' && !client.getRoomById(roomID)!.isSpace) {
      outerContext.go("/rooms/$roomID");
    } else {
      context.go('/rooms/spaces/$roomID/details');
    }
  }

  Future<void> _joinRoom() async {
    if (_isRoomMember) {
      _goToRoom(room!.id);
      Navigator.of(context).pop();
      return;
    }

    final result = await showFutureLoadingDialog<String>(
      context: context,
      future: () async {
        final roomId = await client.joinRoom(
          roomAlias ?? chunk!.roomId,
          serverName: via,
        );

        final room = client.getRoomById(roomId);
        if (room == null || room.membership != Membership.join) {
          await client.waitForRoomInSync(roomId, join: true);
        }
        return roomId;
      },
    );

    if (result.result != null) {
      _goToRoom(result.result!);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _knockRoom() async {
    if (_isRoomMember) {
      _goToRoom(room!.id);
      Navigator.of(context).pop();
      return;
    }

    await showFutureLoadingDialog<String>(
      context: context,
      future: () async => client.knockRoom(
        roomAlias ?? chunk!.roomId,
        via: via,
      ),
      onSuccess: () => L10n.of(context).knockSpaceSuccess,
      delay: false,
    );
  }

  bool testRoom(PublicRoomsChunk r) => r.canonicalAlias == roomAlias;

  Future<PublicRoomsChunk> search() async {
    final chunk = this.chunk;
    if (chunk != null) return chunk;
    final query = await Matrix.of(outerContext).client.queryPublicRooms(
          server: roomAlias!.domain,
          filter: PublicRoomQueryFilter(
            genericSearchTerm: roomAlias,
          ),
        );
    if (!query.chunk.any(testRoom)) {
      throw (L10n.of(outerContext).noRoomsFound);
    }
    return query.chunk.firstWhere(testRoom);
  }

  @override
  Widget build(BuildContext context) {
    final roomAlias = this.roomAlias ?? chunk?.canonicalAlias;
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            chunk?.name ?? roomAlias ?? chunk?.roomId ?? 'Unknown',
            overflow: TextOverflow.fade,
          ),
          actions: [
            Center(
              child: CloseButton(
                onPressed: Navigator.of(context, rootNavigator: false).pop,
              ),
            ),
          ],
        ),
        body: FutureBuilder<PublicRoomsChunk>(
          future: search(),
          builder: (context, snapshot) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                spacing: 32.0,
                children: [
                  Row(
                    spacing: 16.0,
                    children: [
                      (chunk?.avatarUrl != null || chunk?.roomType != 'm.space')
                          ? Avatar(
                              mxContent: chunk?.avatarUrl,
                              name: chunk?.name,
                              size: 160.0,
                              borderRadius: BorderRadius.circular(
                                chunk?.roomType != 'm.space' ? 80 : 24.0,
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(24.0),
                              child: CachedNetworkImage(
                                imageUrl: chunk!.defaultAvatar(),
                                width: 160.0,
                                height: 160.0,
                                fit: BoxFit.cover,
                              ),
                            ),
                      Expanded(
                        child: SizedBox(
                          height: 160.0,
                          child: Column(
                            spacing: 16.0,
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                spacing: 8.0,
                                children: [
                                  const Icon(Icons.group),
                                  Text(
                                    L10n.of(context).countParticipants(
                                      chunk?.numJoinedMembers ?? 1,
                                    ),
                                  ),
                                ],
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  child: Text(
                                    chunk?.topic ??
                                        (chunk?.roomType != 'm.space'
                                            ? L10n.of(context)
                                                .noChatDescriptionYet
                                            : L10n.of(context)
                                                .noSpaceDescriptionYet),
                                    softWrap: true,
                                    textAlign: TextAlign.start,
                                    maxLines: null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    spacing: 8.0,
                    children: _isKnockRoom
                        ? [
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _codeController,
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        hintText:
                                            L10n.of(context).enterSpaceCode,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16.0,
                                        ),
                                        hintStyle: TextStyle(
                                          color: Theme.of(context).hintColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                      ),
                                    ),
                                    child: ElevatedButton(
                                      onPressed: _joinWithCode,
                                      style: ElevatedButton.styleFrom(
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.zero,
                                            bottomLeft: Radius.zero,
                                            topRight: Radius.circular(24),
                                            bottomRight: Radius.circular(24),
                                          ),
                                        ),
                                      ),
                                      child: Text(L10n.of(context).join),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: _knockRoom,
                              child: Row(
                                spacing: 8.0,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Symbols.door_open,
                                    size: 20.0,
                                  ),
                                  Text(L10n.of(context).askToJoin),
                                ],
                              ),
                            ),
                            if (roomAlias != null)
                              ElevatedButton(
                                onPressed: () {
                                  FluffyShare.share(
                                    "${Environment.frontendURL}/#/join_with_alias?alias=${Uri.encodeComponent(roomAlias)}",
                                    context,
                                  );
                                  Navigator.of(context).pop();
                                },
                                child: Row(
                                  spacing: 8.0,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.share_outlined,
                                      size: 20.0,
                                    ),
                                    Flexible(
                                      child: Text(
                                        L10n.of(context).shareSpaceLink,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ]
                        : [
                            ElevatedButton(
                              onPressed: _joinRoom,
                              child: Row(
                                spacing: 8.0,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.join_full_outlined,
                                    size: 20.0,
                                  ),
                                  Text(L10n.of(context).join),
                                ],
                              ),
                            ),
                            if (roomAlias != null)
                              ElevatedButton(
                                onPressed: () {
                                  FluffyShare.share(
                                    "${Environment.frontendURL}/#/join_with_alias?alias=${Uri.encodeComponent(roomAlias)}",
                                    context,
                                  );
                                  Navigator.of(context).pop();
                                },
                                child: Row(
                                  spacing: 8.0,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.share_outlined,
                                      size: 20.0,
                                    ),
                                    Flexible(
                                      child: Text(
                                        L10n.of(context).shareSpaceLink,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
