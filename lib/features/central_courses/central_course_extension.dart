import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/central_courses/central_course_rules.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension CentralCourseRoomExtension on Room {
  bool get isCentralCourse {
    final userId = client.userID;
    final settings = getState(PangeaEventTypes.courseSettings);
    return userId != null &&
        settings != null &&
        CentralCourseRules.isCentralMark(
          settings.content,
          settings.senderId,
          CentralCourseRules.supportUserId(userId),
        );
  }

  bool get isTeachersCourse {
    final userId = client.userID;
    if (userId == null ||
        !isSpace ||
        coursePlan == null ||
        membership != Membership.join) {
      return false;
    }
    final users =
        getState(
          EventTypes.RoomPowerLevels,
        )?.content.tryGetMap<String, Object?>('users') ??
        const {};
    return CentralCourseRules.hasOtherHumanAdmin(
      users,
      self: userId,
      support: CentralCourseRules.supportUserId(userId),
      bot: BotName.byEnvironment,
    );
  }
}

extension CentralCourseClientExtension on Client {
  bool get inTeachersCourse => rooms.any((room) => room.isTeachersCourse);

  /// Answered from local state, so a learner already home costs no catalog
  /// lookup on each app open.
  bool inCentralCourseFor(String language) => rooms.any(
    (room) =>
        room.membership == Membership.join &&
        room.isCentralCourse &&
        room.coursePlan?.l2?.split('-').first == language,
  );

  /// Joins [language]'s central course. Returns its room id when joined now;
  /// null when the language has none, the learner is already in it, or the
  /// join failed (reported).
  Future<String?> joinCentralCourse(String language) async {
    final roomId = await centralCourseFor(language);
    if (roomId == null) return null;
    if (getRoomById(roomId)?.membership == Membership.join) return null;
    try {
      await joinRoom(roomId);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'room_id': roomId, 'target_language': language},
      );
      return null;
    }
    try {
      await waitForRoomInSync(
        roomId,
        join: true,
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Sync lag, not a failed join: the membership is real, and the room
      // arrives with a later sync.
    }
    return roomId;
  }
}

/// The app-open half: an existing learner who qualifies is joined to their
/// language's central course (joining-courses.instructions.md § The central
/// course).
abstract class CentralCourseJoin {
  /// Per user and language, so the app-open and language-change checks can't
  /// both join.
  static final Set<String> _running = {};

  /// The room joined now, for the caller to tell the learner; null when
  /// nothing was joined.
  static Future<String?> joinIfDue(Client client) async {
    await client.roomsLoading;
    await client.accountDataLoading;
    final user = MatrixState.pangeaController.userController;
    await user.initialize();

    final userId = client.userID;
    final language = user.userL2?.langCodeShort;
    final settings = user.profile.userSettings;
    if (userId == null ||
        !CentralCourseRules.qualifies(
          role: settings.selfIdentifiedRole,
          language: language,
          leftLanguages: settings.leftCentralCourses,
          inTeachersCourse: client.inTeachersCourse,
        )) {
      return null;
    }

    if (client.inCentralCourseFor(language!)) return null;

    final key = '$userId $language';
    if (!_running.add(key)) return null;
    try {
      return await client.joinCentralCourse(language);
    } finally {
      _running.remove(key);
    }
  }
}
