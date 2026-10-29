import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/cities/cities_repo.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
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
  /// When the actor is a course admin, the course's own copy (content-studio)
  /// is written from the list this course shows its members once the plan is
  /// attached — see [_writeCourseMissionsCopy].
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
      isRoomAdmin ? await courseScopedOutline(courseId, id) : null,
      planChanged: planChanged,
    );
  }

  /// A new course's own copy for [questId], written by its creator right
  /// after the space exists: snapshotted from the course-scoped list, which
  /// only a member of the course can read with the quest owner's private
  /// activities in it, so it cannot ride in the creation request. A failed or
  /// slow read leaves the course without a copy (logged), reading the shared
  /// quest as before.
  ///
  /// [questId] comes from the creation itself: right after the space arrives
  /// in sync its state can hold only `m.room.create`, so the plan event may
  /// not be readable here yet.
  Future<void> writeNewCourseCopy(String questId) async {
    if (!isRoomAdmin || courseMissions != null) return;
    final outline = await courseScopedOutline(questId, id);
    if (outline == null) {
      ErrorHandler.logError(
        e: 'Course created without its own Can-Do copy: outline not loaded',
        data: {'room_id': id, 'quest_id': questId},
        level: SentryLevel.warning,
      );
      return;
    }
    await _writeCourseMissionsCopy(outline, planChanged: true);
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
  ///
  /// With [Environment.courseMissionsV2Enabled] the copy is the trip (version
  /// 2): each Can-Do sliced to the listed city
  /// most of its activities fall under, from the CMS city list. When that
  /// list cannot be read (logged by the repo) the version 1 snapshot is
  /// written instead, so the course still gets its own list; it reads as a
  /// course not yet sliced into cities.
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
      cities: Environment.courseMissionsV2Enabled
          ? await CitiesRepo.index()
          : null,
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
