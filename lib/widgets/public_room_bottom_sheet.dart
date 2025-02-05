import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

// #Pangea
// class PublicRoomBottomSheet extends StatelessWidget {
class PublicRoomBottomSheet extends StatefulWidget {
  // Pangea#
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

  // #Pangea
  @override
  State<StatefulWidget> createState() => PublicRoomBottomSheetState();
}

class PublicRoomBottomSheetState extends State<PublicRoomBottomSheet> {
  BuildContext get outerContext => widget.outerContext;
  String? get roomAlias => widget.roomAlias;
  PublicRoomsChunk? get chunk => widget.chunk;
  List<String>? get via => widget.via;

  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinWithCode(String code) async {
    await MatrixState.pangeaController.classController.joinClasswithCode(
      context,
      _codeController.text,
      notFoundError: L10n.of(context).notTheCodeError,
    );
  }

  bool get _isRoomMember =>
      chunk != null &&
      Matrix.of(outerContext).client.getRoomById(chunk!.roomId) != null;
  // Pangea#

  void _joinRoom(BuildContext context) async {
    final client = Matrix.of(outerContext).client;
    final chunk = this.chunk;
    final knock = chunk?.joinRule == 'knock';
    final result = await showFutureLoadingDialog<String>(
      context: context,
      future: () async {
        if (chunk != null && client.getRoomById(chunk.roomId) != null) {
          return chunk.roomId;
        }
        final roomId = chunk != null && knock
            ? await client.knockRoom(chunk.roomId, serverName: via)
            : await client.joinRoom(
                roomAlias ?? chunk!.roomId,
                serverName: via,
              );

        if (!knock && client.getRoomById(roomId) == null) {
          await client.waitForRoomInSync(roomId);
        }
        // #Pangea
        final room = client.getRoomById(roomId);
        if (room != null && (await room.leaveIfFull())) {
          throw L10n.of(context).roomFull;
        }
        // Pangea#
        return roomId;
      },
    );
    if (knock) {
      return;
    }
    if (result.error == null) {
      Navigator.of(context).pop<bool>(true);
      // don't open the room if the joined room is a space
      if (chunk?.roomType != 'm.space' &&
          !client.getRoomById(result.result!)!.isSpace) {
        outerContext.go('/rooms/${result.result!}');
      }
      return;
    }
  }

  bool _testRoom(PublicRoomsChunk r) => r.canonicalAlias == roomAlias;

  Future<PublicRoomsChunk> _search() async {
    final chunk = this.chunk;
    if (chunk != null) return chunk;
    final query = await Matrix.of(outerContext).client.queryPublicRooms(
          server: roomAlias!.domain,
          filter: PublicRoomQueryFilter(
            genericSearchTerm: roomAlias,
          ),
        );
    if (!query.chunk.any(_testRoom)) {
      throw (L10n.of(outerContext).noRoomsFound);
    }
    return query.chunk.firstWhere(_testRoom);
  }

  @override
  Widget build(BuildContext context) {
    final roomAlias = this.roomAlias ?? chunk?.canonicalAlias;
    final roomLink = roomAlias ?? chunk?.roomId;
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            chunk?.name ?? roomAlias ?? chunk?.roomId ?? 'Unknown',
            overflow: TextOverflow.fade,
          ),
          leading: Center(
            child: CloseButton(
              onPressed: Navigator.of(context, rootNavigator: false).pop,
            ),
          ),
          actions: roomAlias == null
              ? null
              : [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: IconButton(
                      icon: const Icon(Icons.qr_code_rounded),
                      // #Pangea
                      // onPressed: () => showQrCodeViewer(
                      //   context,
                      //   roomAlias,
                      // ),
                      onPressed: () {
                        FluffyShare.share(
                          "${Environment.frontendURL}/#/join_with_alias?alias=${Uri.encodeComponent(roomAlias)}",
                          context,
                        );
                        Navigator.of(context).pop();
                      },
                      // Pangea#
                    ),
                  ),
                ],
        ),
        body: FutureBuilder<PublicRoomsChunk>(
          future: _search(),
          builder: (context, snapshot) {
            final theme = Theme.of(context);

            final profile = snapshot.data;
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: profile == null
                          ? const Center(
                              child: CircularProgressIndicator.adaptive(),
                            )
                          : Avatar(
                              client: Matrix.of(outerContext).client,
                              mxContent: profile.avatarUrl,
                              name: profile.name ?? roomAlias,
                              size: Avatar.defaultSize * 3,
                            ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton.icon(
                            onPressed: roomLink != null
                                ? () => FluffyShare.share(
                                      roomLink,
                                      context,
                                      copyOnly: true,
                                    )
                                : null,
                            icon: const Icon(
                              Icons.copy_outlined,
                              size: 14,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurface,
                              iconColor: theme.colorScheme.onSurface,
                            ),
                            label: Text(
                              roomLink ?? '...',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.groups_3_outlined,
                              size: 14,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurface,
                              iconColor: theme.colorScheme.onSurface,
                            ),
                            label: Text(
                              L10n.of(context).countParticipants(
                                profile?.numJoinedMembers ?? 0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // #Pangea
                if (!_isRoomMember &&
                    chunk?.roomType == 'm.space' &&
                    chunk?.joinRule != 'public')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextField(
                      controller: _codeController,
                      onSubmitted: (value) => _joinWithCode(value).then(
                        (value) => Navigator.of(context).pop(),
                      ),
                      minLines: 1,
                      maxLines: 1,
                      decoration: InputDecoration(
                        hintText: L10n.of(context).enterCodeToJoin,
                      ),
                    ),
                  ),
                if (!_isRoomMember &&
                    chunk?.roomType == 'm.space' &&
                    chunk?.joinRule != 'public')
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8,
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _joinWithCode(_codeController.text).then(
                        (_) => Navigator.of(context).pop(),
                      ),
                      label: Text(L10n.of(context).joinWithCode),
                      icon: const Icon(Icons.navigate_next),
                    ),
                  ),
                if (!_isRoomMember &&
                    chunk?.roomType == 'm.space' &&
                    chunk?.joinRule != 'public')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 16.0,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppConfig.borderRadius / 3,
                            ),
                            color: theme.colorScheme.surface.withAlpha(128),
                          ),
                          child: Text(
                            L10n.of(context).or,
                            style: TextStyle(
                              fontSize: AppConfig.fontSizeFactor *
                                  AppConfig.messageFontSize,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Pangea#
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton.icon(
                    onPressed: () => _joinRoom(context),
                    label: Text(
                      chunk?.joinRule == 'knock' &&
                              Matrix.of(outerContext)
                                      .client
                                      .getRoomById(chunk!.roomId) ==
                                  null
                          ? L10n.of(context).knock
                          : chunk?.roomType == 'm.space'
                              ? L10n.of(context).joinSpace
                              : L10n.of(context).joinRoom,
                    ),
                    icon: const Icon(Icons.navigate_next),
                  ),
                ),
                const SizedBox(height: 16),
                if (profile?.topic?.isNotEmpty ?? false)
                  ListTile(
                    subtitle: SelectableLinkify(
                      text: profile!.topic!,
                      linkStyle: const TextStyle(
                        color: Colors.blueAccent,
                        decorationColor: Colors.blueAccent,
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium!.color,
                      ),
                      options: const LinkifyOptions(humanize: false),
                      onOpen: (url) =>
                          UrlLauncher(context, url.url).launchUrl(),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
