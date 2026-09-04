import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension ActivitySessionFilledRoomExtension on Room {
  /// The joined course spaces this session is listed under — the course it was
  /// launched from plus every course the launch fanned it out into — which is
  /// exactly the set of course pages showing it as Open.
  Iterable<Room> get _listingCourses => pangeaSpaceParents.where(
    (space) => space.coursePlan != null && space.membership == Membership.join,
  );

  /// Tell every course this session is listed under that its last seat is now
  /// taken (#8735). Coursemates never sync the session room, so the role write
  /// that filled it reaches them only through the world map's discovery pass —
  /// and this event is the sync tick that makes that pass run now, instead of
  /// whenever some unrelated room next updates. Nothing reads the content; it
  /// is there for debugging.
  ///
  /// Best-effort by design: the seat claim that triggers this has already
  /// succeeded, so a course that rejects the send is reported and skipped, and
  /// a missed announcement only means coursemates correct on their next
  /// discovery pass, as they did before.
  Future<void> announceActivitySessionFilled() async {
    final activityId = this.activityId;
    if (activityId == null) {
      ErrorHandler.logError(
        e: "announceActivitySessionFilled called on a non-session room",
        data: {"roomId": id},
      );
      return;
    }
    for (final course in _listingCourses) {
      try {
        await course.sendEvent({
          ActivitySessionConstants.activityId: activityId,
          ActivitySessionConstants.sessionRoomId: id,
        }, type: PangeaEventTypes.activitySessionFilled);
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {"roomId": id, "courseId": course.id},
          level: SentryLevel.warning,
        );
      }
    }
  }
}
