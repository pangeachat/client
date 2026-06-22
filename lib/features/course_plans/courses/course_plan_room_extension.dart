import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/teacher_mode_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

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
          room!.hasPickedRole &&
          !room.hasCompletedRole) {
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
    await client.setRoomStateWithKey(id, PangeaEventTypes.coursePlan, "", {
      "uuid": courseId,
    });
    if (coursePlan?.uuid != courseId) {
      await future;
    }
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
}
