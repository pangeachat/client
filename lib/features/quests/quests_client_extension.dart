import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

/// One value per activity from its sessions' [(activityId, stars)] pairs: the
/// best session's. The per-member reduction every stars reader applies before
/// crediting a family (activity_family.dart).
Map<String, int> bestStarsByActivity(
  Iterable<({String activityId, int stars})> sessions,
) {
  final best = <String, int>{};
  for (final session in sessions) {
    best[session.activityId] = max(
      best[session.activityId] ?? 0,
      session.stars,
    );
  }
  return best;
}

extension QuestsClientExtension on Client {
  /// The learner's best stars per activity, one entry per activity actually
  /// played. Raw per member: readers that answer for a course credit it
  /// across the activity's copies ([CourseCredit], activity_family.dart).
  Map<String, int> get userStarsByActivity => bestStarsByActivity([
    for (final room in rooms)
      if (room.activityId != null)
        (activityId: room.activityId!, stars: room.ownCompletedGoals.length),
  ]);
}
