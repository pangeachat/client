import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/quests/course_progress_event.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// A learner's analytics room as the home of their course progress records,
/// one per course, keyed by the course room id (client#9643).
extension CourseProgressRoomExtension on Room {
  /// The record stored for [courseRoomId], or null when there is none or it
  /// can't be read.
  CourseProgressEvent? courseProgress(String courseRoomId) {
    final state = getState(PangeaEventTypes.courseProgress, courseRoomId);
    if (state == null) return null;
    final record = CourseProgressEvent.fromJson(state.content);
    if (record == null) {
      // Its dates can't be read, so they can't be kept; the next write
      // replaces the record.
      ErrorHandler.logErrorOnce(
        key: 'course-progress-unreadable:$courseRoomId',
        e: 'Stored course progress record could not be read',
        data: {'analyticsRoomId': id, 'courseRoomId': courseRoomId},
        level: SentryLevel.warning,
      );
    }
    return record;
  }

  /// Stores [record] as [courseRoomId]'s.
  Future<void> setCourseProgress(
    String courseRoomId,
    CourseProgressEvent record,
  ) => client.setRoomStateWithKey(
    id,
    PangeaEventTypes.courseProgress,
    courseRoomId,
    record.toJson(),
  );
}
