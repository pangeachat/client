import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';

extension ActivityLockClientExtension on Client {
  /// The course rooms whose progression keeps [activityId] from being
  /// started — empty when it is unlocked. The same outlines and resolver the
  /// map and course panel read (#9333 prototype). Outline reads are cached by
  /// the quest repo, so this is cheap after the first call. A course that
  /// fails to load is reported and skipped, so failure reads unlocked. With
  /// [courseId] (launched from a course), only that course's locks count.
  Future<List<Room>> coursesLockingActivity(
    String activityId, {
    String? courseId,
  }) async {
    final cache = JoinedObjectiveCache();
    await cache.rebuildFromJoinedCourses(
      this,
      onError: reportCourseOutlineFailure,
    );
    return [
      for (final id
          in cache
              .resolution(userStarsByActivity)
              .coursesLocking(activityId, courseId: courseId))
        ?getRoomById(id),
    ];
  }

  Future<bool> isActivityLocked(String activityId, {String? courseId}) async =>
      (await coursesLockingActivity(activityId, courseId: courseId)).isNotEmpty;
}
