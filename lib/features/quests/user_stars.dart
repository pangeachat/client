import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

/// The learner's earned stars per activity, from their own session rooms: stars
/// = goals the learner has collected in a role they hold, kept as the best
/// across multiple sessions of the same activity.
///
/// Used by the activity start page (`not_started_session_controller`) to feed the
/// progression gate. NOTE: the world map does NOT call this helper — it derives
/// the same per-activity star counts independently in
/// `world_map._deriveActivitySignals` and `_userCompletion`. So the two are
/// parallel implementations of the one rule (quests.instructions.md), not a
/// single shared source; keep them in sync, or route the map through this
/// function, until they're unified.
Map<String, int> userStarsByActivity(Client client) {
  final stars = <String, int>{};
  for (final room in client.rooms) {
    final activityId = room.activityId;
    if (activityId == null) continue;
    if (room.ownRole == null) continue;
    final collected = room.ownCompletedGoals.length;
    if (collected > (stars[activityId] ?? 0)) {
      stars[activityId] = collected;
    }
  }
  return stars;
}
