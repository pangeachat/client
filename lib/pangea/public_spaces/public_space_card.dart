import 'dart:math';

import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/public_spaces/public_room_bottom_sheet.dart';
import 'package:fluffychat/pangea/spaces/constants/space_constants.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

class PublicSpaceCard extends StatelessWidget {
  final PublicRoomsChunk space;
  final double width;
  final double height;

  const PublicSpaceCard({
    super.key,
    required this.space,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PressableButton(
      onPressed: () => PublicRoomBottomSheet.show(
        roomAlias: space.canonicalAlias ?? space.roomId,
        chunk: space,
        context: context,
      ),
      borderRadius: BorderRadius.circular(24.0),
      color: theme.brightness == Brightness.dark
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
      colorFactor: theme.brightness == Brightness.dark ? 0.6 : 0.2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24.0),
        ),
        height: height,
        width: width,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(24.0),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: height,
                  width: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24.0),
                    child: space.avatarUrl != null
                        ? MxcImage(
                            uri: space.avatarUrl!,
                            width: width,
                            height: width,
                            fit: BoxFit.cover,
                          )
                        : CachedNetworkImage(
                            imageUrl: SpaceConstants
                                .publicSpaceIcons[Random().nextInt(
                              SpaceConstants.publicSpaceIcons.length,
                            )],
                            width: width,
                            height: width,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      spacing: 4.0,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          spacing: 4.0,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    space.name ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(24.0),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 2.0,
                                horizontal: 8.0,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 8.0,
                                children: [
                                  const Icon(
                                    Icons.group_outlined,
                                    size: 12.0,
                                  ),
                                  Text(
                                    L10n.of(context).countParticipants(
                                      space.numJoinedMembers,
                                    ),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Flexible(
                          child: Text(
                            space.topic ??
                                L10n.of(context).noSpaceDescriptionYet,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                            maxLines: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
