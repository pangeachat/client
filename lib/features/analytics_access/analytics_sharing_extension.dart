import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';

/// Which courses can see the learner's analytics, and taking that away when
/// the learner leaves one (course-analytics-access.instructions.md).
extension AnalyticsSharingClientExtension on Client {
  /// The joined courses whose teachers can see the learner's analytics: one of
  /// the course's teachers is in one of the learner's analytics rooms. Shown
  /// as the shared-courses list in Learning settings.
  Future<List<Room>> coursesSharingAnalytics() async {
    final viewers = await _analyticsViewerIds();
    return [
      for (final course in _joinedCourses())
        if (_teacherIds(course).any(viewers.contains)) course,
    ];
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

  Future<Set<String>> _analyticsViewerIds() async => {
    for (final room in allMyAnalyticsRooms)
      for (final user in await room.requestParticipants([Membership.join]))
        user.id,
  };
}
