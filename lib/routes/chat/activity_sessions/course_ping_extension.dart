import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/activity_sessions/course_ping_constants.dart';

extension CoursePingExtension on Room {
  Future<String?> get unreadCoursePingEventID async {
    try {
      final timeline = await getTimeline();
      final lastCoursePing = timeline.events.firstWhereOrNull(
        (e) => e.isCoursePing,
      );
      if (lastCoursePing == null) return null;

      final lastRead = fullyRead;
      if (lastRead.isEmpty) return lastCoursePing.eventId;

      final event = await getEventById(lastRead);
      if (event == null ||
          lastCoursePing.originServerTs.isAfter(event.originServerTs)) {
        return lastCoursePing.eventId;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> sendActivityPing(String body, {required String activityId}) =>
      sendEvent({
        "body": body,
        "msgtype": MessageTypes.Text,
        CoursePingConstants.coursePingRoomId: id,
        CoursePingConstants.coursePingActivityId: activityId,
      });
}

extension on Event {
  bool get isCoursePing =>
      type == EventTypes.Message &&
      messageType == MessageTypes.Text &&
      content.containsKey(CoursePingConstants.coursePingRoomId) &&
      content.containsKey(CoursePingConstants.coursePingActivityId);
}
