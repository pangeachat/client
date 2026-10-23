import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summaries_model.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';

/// An activity card's live state: what its frame and state pill show, how
/// many open sessions a coursemate is waiting in, and the seats of the
/// learner's own session.
typedef ActivityLiveState = ({
  ActivityPinState? state,
  int openSessions,
  List<String> participants,
  int openSlots,
});

/// No live session: a plain card.
const ActivityLiveState noActivityLiveState = (
  state: null,
  openSessions: 0,
  participants: <String>[],
  openSlots: 0,
);

extension ActivityLiveStateRoomExtension on Room {
  /// [activityId]'s live state in this joined course — the learner's own
  /// unfinished session (ongoing, pending or active) first, else coursemates'
  /// open sessions from the discovery cache (joinable). Shared by the course
  /// page's row, the Mission circles' ping bell and a Learning Objective's
  /// detail page.
  ActivityLiveState activityLiveState(String activityId) {
    final ongoingId = activeActivityRoomId(activityId);
    if (ongoingId != null) {
      final live = client.getRoomById(ongoingId);
      final remaining = live?.numRemainingRoles ?? 0;
      return (
        state: remaining > 0
            ? ActivityPinState.ongoingPending
            : ActivityPinState.ongoingActive,
        openSessions: 0,
        participants: live?.largeCardParticipantIds ?? const [],
        openSlots: remaining,
      );
    }

    final cached = DiscoveredSessionsCache.instance.forActivity(
      activityId,
      course: this,
    );
    final open = cached == null
        ? 0
        : ActivitySessionSummariesModel(
            cached,
            activityId: activityId,
          ).openSessions.length;
    return open > 0
        ? (
            state: ActivityPinState.joinable,
            openSessions: open,
            participants: const [],
            openSlots: 0,
          )
        : noActivityLiveState;
  }
}
