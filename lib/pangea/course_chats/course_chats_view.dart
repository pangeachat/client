import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/course_chats/course_chats_page.dart';
import 'package:fluffychat/pangea/courses/course_plan_builder.dart';
import 'package:fluffychat/pangea/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseChatsView extends StatelessWidget {
  final CourseChatsController controller;
  const CourseChatsView(
    this.controller, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    if (room == null) {
      return const Center(
        child: Icon(
          Icons.search_outlined,
          size: 80,
        ),
      );
    }

    final theme = Theme.of(context);
    return StreamBuilder(
      stream: room.client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final childrenIds =
            room.spaceChildren.map((c) => c.roomId).whereType<String>().toSet();

        final joinedRooms = room.client.rooms
            .where((room) => childrenIds.remove(room.id))
            .where((room) => !room.isHiddenRoom)
            .toList();

        final joinedChats = [];
        final joinedSessions = [];
        for (final joinedRoom in joinedRooms) {
          joinedRoom.isActivitySession
              ? joinedSessions.add(joinedRoom)
              : joinedChats.add(joinedRoom);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 12.0,
            horizontal: 8.0,
          ),
          child: CoursePlanBuilder(
            courseId: room.coursePlan?.uuid,
            builder: (context, courseController) {
              return ListView.builder(
                shrinkWrap: true,
                itemCount: joinedRooms.length +
                    (controller.discoveredChildren?.length ?? 0) +
                    4,
                itemBuilder: (context, i) {
                  // courses chats title
                  if (i == 0) {
                    if (FluffyThemes.isColumnMode(context)) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10.0),
                        child: Column(
                          spacing: 12.0,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 24.0),
                            const Icon(
                              Icons.chat_bubble_outline,
                              size: 30.0,
                            ),
                            Text(
                              L10n.of(context).courseChats,
                              style: const TextStyle(fontSize: 12.0),
                            ),
                            const SizedBox(height: 14.0),
                          ],
                        ),
                      );
                    }

                    return const SizedBox();
                  }
                  i--;

                  // joined group chats
                  if (i < joinedChats.length) {
                    final joinedRoom = joinedChats[i];
                    return ChatListItem(
                      joinedRoom,
                      onTap: () => controller.onChatTap(joinedRoom),
                      onLongPress: (context) => controller.chatContextAction(
                        joinedRoom,
                        context,
                      ),
                      activeChat: controller.widget.activeChat == joinedRoom.id,
                    );
                  }
                  i -= joinedChats.length;

                  if (i == 0) {
                    if (room.coursePlan == null ||
                        (courseController.course == null &&
                            !courseController.loading)) {
                      return const SizedBox();
                    }

                    Topic? topic;
                    final course = courseController.course;
                    if (course != null) {
                      topic = room.currentTopic(
                        room.client.userID!,
                        course,
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                        horizontal: 8.0,
                      ),
                      child: courseController.loading
                          ? LinearProgressIndicator(
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius,
                              ),
                            )
                          : topic != null
                              ? Row(
                                  spacing: 6.0,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.location_on, size: 24.0),
                                    Text(
                                      topic.location,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox(),
                    );
                  }
                  i--;

                  // joined activity sessions
                  if (i < joinedSessions.length) {
                    final joinedRoom = joinedSessions[i];
                    return ChatListItem(
                      joinedRoom,
                      onTap: () => controller.onChatTap(joinedRoom),
                      onLongPress: (context) => controller.chatContextAction(
                        joinedRoom,
                        context,
                      ),
                      activeChat: controller.widget.activeChat == joinedRoom.id,
                    );
                  }
                  i -= joinedSessions.length;

                  if (i == 0) {
                    return SearchTitle(
                      title: L10n.of(context).discover,
                      icon: const Icon(Icons.explore_outlined),
                    );
                  }
                  i--;
                  if (i == (controller.discoveredChildren?.length ?? 0)) {
                    if (controller.noMoreRooms) {
                      return Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Center(
                          child: Text(
                            L10n.of(context).noMoreChatsFound,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 2.0,
                      ),
                      child: TextButton(
                        onPressed: controller.isLoading
                            ? null
                            : controller.loadHierarchy,
                        child: controller.isLoading
                            ? LinearProgressIndicator(
                                borderRadius: BorderRadius.circular(
                                  AppConfig.borderRadius,
                                ),
                              )
                            : Text(L10n.of(context).loadMore),
                      ),
                    );
                  }
                  final item = controller.discoveredChildren![i];
                  final displayname = item.name ??
                      item.canonicalAlias ??
                      L10n.of(context).emptyChat;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 1,
                    ),
                    child: Material(
                      borderRadius:
                          BorderRadius.circular(AppConfig.borderRadius),
                      clipBehavior: Clip.hardEdge,
                      child: ListTile(
                        visualDensity: const VisualDensity(vertical: -0.5),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        onTap: () => controller.joinChildRoom(item),
                        leading: Avatar(
                          mxContent: item.avatarUrl,
                          name: displayname,
                          userId: Matrix.of(context)
                              .client
                              .getRoomById(item.roomId)
                              ?.directChatMatrixID,
                          borderRadius: item.roomType == 'm.space'
                              ? BorderRadius.circular(
                                  AppConfig.borderRadius / 2,
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              item.numJoinedMembers.toString(),
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.textTheme.bodyMedium!.color,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.people_outlined,
                              size: 14,
                            ),
                          ],
                        ),
                        subtitle: Text(
                          item.topic ??
                              L10n.of(context).countParticipants(
                                item.numJoinedMembers,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
