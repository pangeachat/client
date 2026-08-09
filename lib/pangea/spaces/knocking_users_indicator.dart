import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/knocking_users_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';

class KnockingUsersIndicator extends StatelessWidget {
  final Room room;
  const KnockingUsersIndicator({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return KnockingUsersBuilder(
      room: room,
      builder: (context, knockingUsers) => AnimatedSize(
        duration: FluffyThemes.animationDuration,
        child: knockingUsers.isEmpty
            ? const SizedBox()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Material(
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  clipBehavior: Clip.hardEdge,
                  child: ListTile(
                    minVerticalPadding: 0,
                    trailing: Icon(
                      Icons.adaptive.arrow_forward_outlined,
                      size: 16,
                    ),
                    title: Row(
                      spacing: 8.0,
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        Expanded(
                          child: Text(
                            knockingUsers.length == 1
                                ? L10n.of(context).aUserIsKnocking
                                : L10n.of(
                                    context,
                                  ).usersAreKnocking(knockingUsers.length),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      // world_v2: token nav to the course's invite page scoped to
                      // this space, with the knock filter riding in the
                      // `coursepage:invite/knock` token param.
                      context.go(
                        WorkspaceNav.openCoursePageFor(
                          GoRouterState.of(context).uri,
                          room.id,
                          RoomSubpageEnum.invite,
                          filter: InvitationFilter.knocking,
                        ),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}
