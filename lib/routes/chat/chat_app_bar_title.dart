import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/presence_builder.dart';

class ChatAppBarTitle extends StatelessWidget {
  final ChatController controller;
  const ChatAppBarTitle(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final VoidCallback? openDetails =
        controller.isArchived
            // #Pangea
            ||
            controller.room.hasArchivedActivity
        // Pangea#
        ? null
        : () => NavigationUtil.goToSpaceRoute(room.id, ['details'], context);
    // The title is an InkWell with no role of its own: name it by its visible
    // text (room name and presence) and say what the tap does (#8849).
    return Semantics(
      container: true,
      button: openDetails != null,
      hint: openDetails != null ? L10n.of(context).chatDetails : null,
      child: InkWell(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: openDetails,
        child: Row(
          children: [
            Hero(
              tag: 'content_banner',
              child: ExcludeSemantics(
                child: Avatar(
                  mxContent: room.avatar,
                  name: room.getLocalizedDisplayname(
                    MatrixLocals(L10n.of(context)),
                  ),
                  // #Pangea
                  userId: room.directChatMatrixID,
                  // Pangea#
                  size: 32,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    room.getLocalizedDisplayname(
                      MatrixLocals(L10n.of(context)),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluffyThemes.isColumnMode(context)
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                  PresenceBuilder(
                    userId: room.directChatMatrixID,
                    builder: (context, presence) {
                      final lastActiveTimestamp = presence?.lastActiveTimestamp;
                      final style = TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      );
                      if (presence?.currentlyActive == true) {
                        return Text(
                          L10n.of(context).currentlyActive,
                          style: style,
                        );
                      }
                      if (lastActiveTimestamp != null) {
                        return Text(
                          L10n.of(context).lastActiveAgo(
                            lastActiveTimestamp.localizedTimeShort(context),
                          ),
                          style: style,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
