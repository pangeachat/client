import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/teacher_mode_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension CoursePlanRoomExtension on Room {
  CoursePlanEvent? get coursePlan {
    final event = getState(PangeaEventTypes.coursePlan);
    if (event == null) return null;
    return CoursePlanEvent.tryParse(event.content);
  }

  /// Course members available to fill an activity's roles, mirroring the start
  /// page's invite math: joined/invited/knocking members, plus the bot when it
  /// is not already a member (it fills one seat). Course-only — independent of
  /// any single activity — so callers compare it against each activity's
  /// `req.numberOfParticipants`. See
  /// `NotStartedSessionController.neededCourseParticipants`.
  Future<int> availableActivityParticipants() async {
    final participants = await requestParticipants(
      const [Membership.join, Membership.invite, Membership.knock],
      false,
      true,
    );
    final hasBot = participants.any((p) => p.id == BotName.byEnvironment);
    return participants.length + (hasBot ? 0 : 1);
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
  ///
  /// [shownOutline] is the quest's outline as the attach page showed it; when
  /// given and the actor is a course admin, the course's own copy
  /// (content-studio) is written from it — see [_writeCourseMissionsCopy].
  Future<void> addCourseToSpace(
    String courseId, {
    required String targetLanguage,
    QuestOutline? shownOutline,
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
    final planChanged = current?.uuid != courseId;
    // Rewrite when the language is missing or stale as well as when the quest
    // changes, so a space attached before `l2` was recorded is repaired here.
    if (planChanged || current?.l2 != desired.l2) {
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
    // After the plan, so no reader pairs the new copy with the old quest.
    await _writeCourseMissionsCopy(
      shownOutline?.quest.id == courseId ? shownOutline : null,
      planChanged: planChanged,
    );
  }

  /// Write the course's own copy when attaching a plan: admin only (readers
  /// ignore a copy whose sender is below power level 100 anyway). Written
  /// when the space has no copy yet, or when the plan changes — an old copy
  /// would name the previous quest's Can-Dos. The snapshot is the list the
  /// course shows without a copy, so this space's pins apply. A revision
  /// above any existing copy's lets open surfaces refresh.
  ///
  /// A plan change with no snapshot to hand ([outline] null) clears the old
  /// quest's copy with an empty record, so readers fall back to the new
  /// shared quest rather than listing the old quest's Can-Dos.
  Future<void> _writeCourseMissionsCopy(
    QuestOutline? outline, {
    required bool planChanged,
  }) async {
    if (!isRoomAdmin) return;
    final existing = courseMissions;
    if (existing != null && !planChanged) return;
    if (outline == null) {
      if (existing == null) return;
      ErrorHandler.logError(
        e: 'Plan replaced without a Can-Do snapshot; course copy cleared',
        data: {'room_id': id},
        level: SentryLevel.warning,
      );
      await client.setRoomStateWithKey(
        id,
        PangeaEventTypes.courseMissions,
        '',
        const <String, dynamic>{},
      );
      return;
    }
    final snapshot = CourseMissionsEvent.snapshotOf(
      outline.restrictedTo(teacherMode.pinnedActivitiesByObjective),
      revision: (existing?.revision ?? 0) + 1,
    );
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.courseMissions,
      '',
      snapshot.toJson(),
    );
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
