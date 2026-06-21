import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

/// The learner's earned stars per activity, from their own session rooms: stars
/// = goals the learner has collected in a role they hold, kept as the best
/// across multiple sessions of the same activity.
///
/// The single source for progression-gate stars: the activity start page
/// (`not_started_session_controller`) and the world map
/// (`world_map._deriveActivitySignals`) both feed the gate from this function, so
/// their lock state cannot drift (quests.instructions.md). The top-right cluster's
/// running total (`world_user_cluster._totalStars`) is computed separately, from
/// `orchestratorAwardedGoals`, because it must work before the activity plan
/// hydrates (this function needs `ownRole`, which needs the plan); keep that one
/// in sync if the star rule changes.
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
