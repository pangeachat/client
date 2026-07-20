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
    return CoursePlanEvent.tryParse(event.content);
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

  /// [targetLanguage] is required because the public course catalog filters on
  /// it: a course space whose plan event carries no `l2` is excluded from every
  /// language-filtered browse, so attaching a quest without it hides the course.
  Future<void> addCourseToSpace(
    String courseId, {
    required String targetLanguage,
  }) async {
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

    final desired = CoursePlanEvent(uuid: courseId, l2: targetLanguage);
    final current = coursePlan;
    // Rewrite when the language is missing or stale as well as when the quest
    // changes, so a space attached before `l2` was recorded is repaired here.
    if (current?.uuid == courseId && current?.l2 == desired.l2) return;
    final future = waitForRoomInSync();
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.coursePlan,
      "",
      desired.toJson(),
    );
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
