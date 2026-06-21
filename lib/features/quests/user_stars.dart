import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

/// The learner's earned stars per activity, from their own session rooms: stars
/// = goals the learner has collected in a role they hold, kept as the best
/// across multiple sessions of the same activity.
///
/// This is the same computation `world_map._deriveActivitySignals` feeds into
/// the progression gate; kept here so other surfaces (e.g. the activity start
/// page) gate identically — the gate is "resolved once" (quests.instructions.md).
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
