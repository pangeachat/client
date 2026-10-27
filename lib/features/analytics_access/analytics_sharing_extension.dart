import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';

/// A joined course with those of its teachers who can see the learner's
/// analytics.
class SharedCourse {
  final Room course;
  final List<User> teachers;

  const SharedCourse({required this.course, required this.teachers});
}

/// Who can see the learner's analytics, as Learning settings lists it: each
/// course with its teachers who can, then everyone else who can, whom the
/// learner may remove (course-analytics-access.instructions.md).
class AnalyticsSharing {
  final List<SharedCourse> courses;
  final List<User> others;

  const AnalyticsSharing({required this.courses, required this.others});

  bool get isEmpty => courses.isEmpty && others.isEmpty;
}

/// Who can see the learner's analytics, and taking that away when the learner
/// leaves a course or removes someone (course-analytics-access.instructions.md).
extension AnalyticsSharingClientExtension on Client {
  /// Everyone joined to one of the learner's analytics rooms, grouped by the
  /// joined courses they teach; those who teach none of them are [others].
  Future<AnalyticsSharing> analyticsSharing() async {
    final viewers = await _analyticsViewers();
    final teaching = <String>{};
    final courses = <SharedCourse>[];
    for (final course in _joinedCourses()) {
      final teacherIds = _teacherIds(course);
      teaching.addAll(teacherIds);
      final teachers = [
        for (final id in teacherIds)
          if (viewers[id] != null) viewers[id]!,
      ];
      if (teachers.isNotEmpty) {
        courses.add(SharedCourse(course: course, teachers: teachers));
      }
    }
    return AnalyticsSharing(
      courses: courses,
      others: [
        for (final viewer in viewers.values)
          if (!teaching.contains(viewer.id)) viewer,
      ],
    );
  }

  /// Takes [userId] out of every one of the learner's analytics rooms. Offered
  /// only for someone who teaches none of the learner's courses, since a
  /// course's teachers seeing its students is a condition of membership. A
  /// failure is thrown to the caller, which shows it.
  Future<void> removeAnalyticsViewer(String userId) async {
    for (final analyticsRoom in allMyAnalyticsRooms) {
      final members = await analyticsRoom.requestParticipants([
        Membership.join,
        Membership.invite,
      ]);
      if (members.any((u) => u.id == userId)) {
        await analyticsRoom.kick(userId);
      }
    }
  }

  /// When the learner leaves [course], its teachers stop seeing their
  /// analytics: each is removed from the learner's analytics rooms, unless
  /// they also teach another course the learner is in
  /// ("Leaving stops the sharing"). Runs before the leave, while the course's
  /// teachers can still be read; a teacher who cannot be removed is reported
  /// and the rest still are.
  Future<void> removeCourseTeachersFromAnalytics(Room course) async {
    final stillTeaching = {
      for (final other in _joinedCourses())
        if (other.id != course.id) ..._teacherIds(other),
    };
    final leaving = _teacherIds(course).difference(stillTeaching);
    if (leaving.isEmpty) return;

    for (final analyticsRoom in allMyAnalyticsRooms) {
      final members = await analyticsRoom.requestParticipants([
        Membership.join,
        Membership.invite,
      ]);
      for (final member in members.where((u) => leaving.contains(u.id))) {
        try {
          await analyticsRoom.kick(member.id);
        } catch (e, s) {
          ErrorHandler.logError(
            e: e,
            s: s,
            data: {
              "course_id": course.id,
              "analytics_room_id": analyticsRoom.id,
            },
            level: PangeaHttpException.severityOf(e),
          );
        }
      }
    }
  }

  Iterable<Room> _joinedCourses() =>
      rooms.where((r) => r.isSpace && r.membership == Membership.join);

  /// A course's teachers by power level, which is always in local state, unlike
  /// the member list: everyone at admin level but the bot and the learner.
  Set<String> _teacherIds(Room course) {
    final users = course
        .getState(EventTypes.RoomPowerLevels)
        ?.content
        .tryGetMap<String, Object?>('users');
    return {
      for (final entry in users?.entries ?? <MapEntry<String, Object?>>[])
        if (entry.value is int &&
            (entry.value as int) >= SpaceConstants.powerLevelOfAdmin &&
            entry.key != BotName.byEnvironment &&
            entry.key != userID)
          entry.key,
    };
  }

  /// Everyone but the learner and the bot joined to one of the learner's
  /// analytics rooms, by id.
  Future<Map<String, User>> _analyticsViewers() async => {
    for (final room in allMyAnalyticsRooms)
      for (final user in await room.requestParticipants([Membership.join]))
        if (user.id != userID && user.id != BotName.byEnvironment)
          user.id: user,
  };
}
