import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_play_badge.dart';
import 'package:fluffychat/routes/chat_list/extended_space_rooms_chunk.dart';
import 'package:fluffychat/routes/chat_list/open_roles_indicator.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class ActivityTemplateChatListItem extends StatelessWidget {
  final Room space;
  final List<ExtendedSpaceRoomsChunk> sessions;
  final Function(ExtendedSpaceRoomsChunk) joinActivity;

  const ActivityTemplateChatListItem({
    super.key,
    required this.space,
    required this.sessions,
    required this.joinActivity,
  });

  @override
  Widget build(BuildContext context) {
    final activity = sessions.first.activity;
    final hero = activity.heroBlock;
    final heroIsVideo = hero != null && (hero.isVideo || hero.isYoutube);
    final heroDisplayUrl = hero?.displayUrl(Avatar.defaultSize);
    final heroUrl = heroDisplayUrl != null
        ? Uri.tryParse(heroDisplayUrl)
        : activity.imageURL;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Column(
        spacing: 10.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            clipBehavior: Clip.hardEdge,
            child: ListTile(
              visualDensity: const VisualDensity(vertical: -0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Stack(
                alignment: Alignment.center,
                children: [
                  ImageByUrl(
                    imageUrl: heroUrl,
                    width: Avatar.defaultSize,
                    borderRadius: BorderRadius.circular(
                      AppConfig.borderRadius / 2,
                    ),
                    replacement: Avatar(
                      name: activity.title,
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius / 2,
                      ),
                    ),
                  ),
                  if (heroIsVideo) const ActivityMediaPlayBadge(size: 16.0),
                ],
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      activity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...sessions.map((e) {
            return Padding(
              padding: const EdgeInsets.only(
                top: 4.0,
                bottom: 4.0,
                right: 4.0,
                left: 14.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: OpenRolesIndicator(
                      roles: e.activity.roles.values.toList(),
                      assignedRoles: e.assignedRoles,
                      space: space,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 24.0),
                    child: ElevatedButton(
                      onPressed: () => showFutureLoadingDialog(
                        context: context,
                        future: () => joinActivity(e),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                      ),
                      child: Text(
                        L10n.of(context).join,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
