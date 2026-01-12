import 'dart:math';

import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/chat/constants/default_power_level.dart';
import 'package:fluffychat/pangea/chat_settings/constants/pangea_room_types.dart';
import 'package:fluffychat/pangea/course_chats/course_chats_settings_model.dart';
import 'package:fluffychat/pangea/course_chats/course_default_chats_enum.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/pangea/course_settings/teacher_mode_model.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/extensions/join_rule_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';

extension CoursePlanRoomExtension on Room {
  CoursePlanEvent? get coursePlan {
    final event = getState(PangeaEventTypes.coursePlan);
    if (event == null) return null;
    return CoursePlanEvent.fromJson(event.content);
  }

  String? activeActivityRoomId(String activityId) {
    for (final child in spaceChildren) {
      if (child.roomId == null) continue;
      final room = client.getRoomById(child.roomId!);
      if (room?.membership == Membership.join &&
          room?.activityId == activityId &&
          !room!.hasArchivedActivity) {
        return room.id;
      }
    }
    return null;
  }

  Future<void> addCourseToSpace(String courseId) async {
    // Ensure students in course can launch activity rooms
    final powerLevels = Map<String, dynamic>.from(
      getState(EventTypes.RoomPowerLevels)?.content ?? {},
    );
    powerLevels['events'] ??= <String, dynamic>{};
    final events = Map<String, dynamic>.from(powerLevels['events']);
    if (events["m.space.child"] != 0) {
      events["m.space.child"] = 0;
      powerLevels['events'] = events;
      await client.setRoomStateWithKey(
        id,
        EventTypes.RoomPowerLevels,
        '',
        powerLevels,
      );
    }

    if (coursePlan?.uuid == courseId) return;
    final future = waitForRoomInSync();
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.coursePlan,
      "",
      {
        "uuid": courseId,
      },
    );
    if (coursePlan?.uuid != courseId) {
      await future;
    }
  }

  Future<String> launchActivityRoom(
    ActivityPlanModel activity,
    ActivityRole? role,
  ) async {
    final roomID = await client.createRoom(
      creationContent: {
        'type': "${PangeaRoomTypes.activitySession}:${activity.activityId}",
      },
      visibility: sdk.Visibility.private,
      name: activity.title,
      topic: activity.description,
      initialState: [
        StateEvent(
          type: PangeaEventTypes.activityPlan,
          content: activity.toJson(),
        ),
        if (activity.imageURL != null)
          StateEvent(
            type: EventTypes.RoomAvatar,
            content: {'url': activity.imageURL!},
          ),
        if (role != null)
          StateEvent(
            type: PangeaEventTypes.activityRole,
            content: ActivityRolesModel({
              role.id: ActivityRoleModel(
                id: role.id,
                userId: client.userID!,
                role: role.name,
              ),
            }).toJson(),
          ),
        RoomDefaults.defaultPowerLevels(
          client.userID!,
        ),
        await client.pangeaJoinRules(
          'knock_restricted',
          allow: [
            {
              "type": "m.room_membership",
              "room_id": id,
            }
          ],
        ),
      ],
    );

    await addToSpace(roomID);
    if (pangeaSpaceParents.isEmpty) {
      await client.waitForRoomInSync(roomID);
    }
    return roomID;
  }

  TeacherModeModel get teacherMode {
    final state = getState(PangeaEventTypes.teacherMode);
    if (state == null) {
      return const TeacherModeModel(enabled: false);
    }
    return TeacherModeModel.fromJson(state.content);
  }

  bool get isTeacherMode => teacherMode.enabled && isRoomAdmin;

  Future<void> setTeacherMode(TeacherModeModel model) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.teacherMode,
      '',
      model.toJson(),
    );
  }

  CourseChatsSettingsModel get courseChatsSettings {
    final event = getState(PangeaEventTypes.courseChatList);
    if (event == null) {
      return const CourseChatsSettingsModel();
    }
    return CourseChatsSettingsModel.fromJson(event.content);
  }

  Future<void> setCourseChatsSettings(
    CourseChatsSettingsModel settings,
  ) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.courseChatList,
      "",
      settings.toJson(),
    );
  }

  bool hasDefaultChat(CourseDefaultChatsEnum type) => pangeaSpaceChildren.any(
        (r) => r.canonicalAlias.localpart?.startsWith(type.alias) == true,
      );

  bool dismissedDefaultChat(CourseDefaultChatsEnum type) {
    switch (type) {
      case CourseDefaultChatsEnum.introductions:
        return courseChatsSettings.dismissedIntroChat;
      case CourseDefaultChatsEnum.announcements:
        return courseChatsSettings.dismissedAnnouncementsChat;
    }
  }

  Future<String> addDefaultChat({
    required CourseDefaultChatsEnum type,
    required String name,
  }) async {
    final random = Random();
    final String uploadURL = switch (type) {
      CourseDefaultChatsEnum.introductions => SpaceConstants
          .introChatIcons[random.nextInt(SpaceConstants.introChatIcons.length)],
      CourseDefaultChatsEnum.announcements =>
        SpaceConstants.announcementChatIcons[
            random.nextInt(SpaceConstants.announcementChatIcons.length)],
    };

    final resp = await client.createRoom(
      preset: CreateRoomPreset.publicChat,
      visibility: Visibility.private,
      name: name,
      roomAliasName: "${type.alias}_${id.localpart}",
      initialState: [
        StateEvent(
          type: EventTypes.RoomAvatar,
          content: {'url': uploadURL},
        ),
        RoomDefaults.defaultPowerLevels(client.userID!),
        await client.pangeaJoinRules(
          'knock_restricted',
          allow: [
            {
              "type": "m.room_membership",
              "room_id": id,
            }
          ],
        ),
      ],
    );

    final room = client.getRoomById(resp);
    if (room == null) {
      await client.waitForRoomInSync(resp, join: true);
    }

    await addToSpace(resp);
    return resp;
  }
}
