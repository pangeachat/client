import 'dart:math';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';

extension QuestsClientExtension on Client {
  /// The learner's sparkles per activity: their best single session's
  /// orchestrator-awarded goals. Drawn on activity cards and map pins; it no
  /// longer decides Mission completion, which [userXpByActivity] feeds.
  Map<String, int> get userStarsByActivity {
    final stars = <String, int>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null) continue;

      final current = stars[activityId] ?? 0;
      final collected = room.ownCompletedGoals.length;
      stars[activityId] = max(current, collected);
    }
    return stars;
  }

  /// The XP the learner has earned per activity, summed over EVERY session of
  /// it, each session's XP raised by [kSparkleXpBonus] per sparkle earned
  /// there. [xpByRoom] is the learner's construct-use XP grouped by the room
  /// it was earned in (MissionXpCache). Repeat sessions accumulate — XP is
  /// effort, unlike the per-activity sparkle best above (#9420; see
  /// quests.instructions.md, "What fills a Mission").
  Map<String, int> userXpByActivity(Map<String, int> xpByRoom) {
    final xp = <String, int>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null) continue;
      final roomXp = xpByRoom[room.id] ?? 0;
      if (roomXp <= 0) continue;
      final sparkles = room.ownCompletedGoals.length;
      final boosted = (roomXp * (1 + kSparkleXpBonus * sparkles)).round();
      xp[activityId] = (xp[activityId] ?? 0) + boosted;
    }
    return xp;
  }
}
