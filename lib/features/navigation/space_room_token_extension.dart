import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/notifications/notification_tap_utils.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_extension.dart';

extension SpaceRoomTokenExtension on Room {
  /// Where a room token naming this space goes instead, since a space has no
  /// chat: a course ping opens its activity, anything else opens the course.
  Future<String> spaceTokenReplacement(Uri current, {String? eventId}) async {
    final ping = eventId == null ? null : await _coursePing(eventId);
    final sessionRoomId = ping?.coursePingSessionRoomId;
    final activityId = ping?.coursePingActivityId;
    if (sessionRoomId != null && activityId != null) {
      return client.coursePingLocation(
        current,
        courseRoomId: id,
        sessionRoomId: sessionRoomId,
        activityId: activityId,
      );
    }
    final withoutToken = roomTokenCloseLocation(current, id);
    return WorkspaceNav.openCourse(
      withoutToken == null ? current : Uri.parse(withoutToken),
      id,
    );
  }

  Future<Event?> _coursePing(String eventId) async {
    try {
      final event = await getEventById(eventId);
      return event != null && event.isCoursePing ? event : null;
    } catch (e, s) {
      // The course still opens; only the jump to the ping's activity is lost.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': id, 'eventId': eventId},
      );
      return null;
    }
  }
}
