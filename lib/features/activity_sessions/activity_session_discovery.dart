import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

/// Discovery of activity-session rooms across the learner's joined courses.
///
/// The one shared answer to "which session rooms exist for my courses'
/// activities", used by both the world map's joinable-pin signals and the
/// activity start page's join list — so both resolve it the same way, from the
/// **server** hierarchy and independent of any single course in scope (a bare
/// map pin carries none). See world-map.instructions.md.
extension ActivitySessionDiscovery on Client {
  /// The learner's joined course spaces (a joined space carrying a course plan).
  List<Room> get joinedCourseSpaces => rooms
      .where(
        (r) =>
            r.isSpace &&
            r.membership == Membership.join &&
            r.coursePlan != null,
      )
      .toList();

  /// Room ids of activity-session children across [joinedCourseSpaces], read from
  /// the server hierarchy so a coursemate's session (absent from `client.rooms`)
  /// is included. Optionally scoped to a single [activityId] by room type.
  /// Best-effort per course; a failed hierarchy read is logged and skipped.
  Future<Set<String>> courseActivitySessionRoomIds({String? activityId}) async {
    final exactType = activityId != null
        ? '${PangeaRoomTypes.activitySession}:$activityId'
        : null;
    final ids = <String>{};
    for (final space in joinedCourseSpaces) {
      try {
        final hierarchy = await getSpaceHierarchy(
          space.id,
          maxDepth: 1,
          limit: 100,
        );
        for (final child in hierarchy.rooms) {
          if (child.roomId == space.id) continue; // the space root itself
          final type = child.roomType;
          if (type == null ||
              !type.startsWith(PangeaRoomTypes.activitySession)) {
            continue; // only activity-session rooms
          }
          if (exactType != null && type != exactType) continue;
          ids.add(child.roomId);
        }
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          m: 'course space hierarchy fetch failed',
          data: {'spaceId': space.id},
        );
      }
    }
    return ids;
  }
}
