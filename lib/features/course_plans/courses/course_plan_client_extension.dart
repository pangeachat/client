import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

extension CoursePlanClientExtension on Client {
  Room? getRoomByCourseId(String courseId) =>
      rooms.firstWhereOrNull((room) => room.coursePlan?.uuid == courseId);

  /// A new course's own copy, from the list its members are shown. Never
  /// fails the creation: an error is logged and the course reads the shared
  /// quest until the Studio's first publish.
  Future<void> writeNewCourseCopy(String spaceId, String questId) async {
    try {
      final room = getRoomById(spaceId);
      if (room == null) {
        ErrorHandler.logError(
          e: 'Course created without its own Can-Do copy: room not in sync',
          data: {'room_id': spaceId},
          level: SentryLevel.warning,
        );
        return;
      }
      await room.writeNewCourseCopy(questId);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'room_id': spaceId},
        level: SentryLevel.warning,
      );
    }
  }
}
