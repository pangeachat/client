import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_signals.dart';

extension WorldMapClientExtension on Client {
  Room? bestJoinableActivityInstance(String activityId) {
    Room? best;
    for (final r in rooms) {
      if (r.activityId != activityId) continue;
      if (!(r.numRemainingRoles > 0 && r.ownRoleState == null)) continue;
      final ms = r.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      final bestMs =
          best?.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      if (best == null || ms > bestMs) best = r;
    }
    return best;
  }

  Map<String, MapCompletionFilter> get activityCompletionStatuses {
    final facts = <ActivityCompletionFacts>[];
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null) continue;

      final role = room.ownRole;
      if (role == null) continue;

      facts.add((
        activityId: activityId,
        totalGoals: role.allGoals.length,
        collectedGoals: room.ownCompletedGoals.length,
      ));
    }
    return WorldMapSignalUtils.reduceActivityCompletions(facts);
  }

  List<ActivitySessionFacts> get _activitySessionFacts => rooms
      .map((r) {
        final activityId = r.activityId;
        if (activityId == null) return null;

        final role = r.ownRole;
        return ActivitySessionFacts(
          activityId: activityId,
          holdsRole: role != null,
          collectedGoals: role != null ? r.ownCompletedGoals.length : 0,
          totalGoals: role?.allGoals.length ?? 0,
          // A free role the user hasn't taken → joinable (the open-session state).
          joinable: r.numRemainingRoles > 0 && r.ownRoleState == null,
          lastEventMs: r.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0,
        );
      })
      .whereType<ActivitySessionFacts>()
      .toList();

  /// Derive each activity's live [PinSignals] from the user's Matrix rooms: the
  /// highest-wins colour state on the `unlocked < joinable` ladder, a 0..1
  /// completion fraction (stars earned toward the activity's total), recency for
  /// the newest open session, and the pinged flag. Also returns the learner's star
  /// total per activity (max across their sessions of it) for the progression
  /// resolver's per-Mission star rollup.
  ///
  /// State derives from sessions the client can see locally: the user's own
  /// sessions give unlocked, and any visible session with a free role the user
  /// isn't bound to gives joinable. Open sessions by strangers are not in
  /// `client.rooms`, so map-wide open-session discovery needs a backend endpoint
  /// (see world-map.instructions.md). Nothing is ever locked — progression only
  /// ranks, never gates (#7186, quests.instructions.md).
  Map<String, PinSignals> deriveActivitySignals({
    required Set<String> pingedActivityIds,
  }) => WorldMapSignalUtils.reduceActivitySignals(
    _activitySessionFacts,
    pingedActivityIds: pingedActivityIds,
    nowMs: DateTime.now().millisecondsSinceEpoch,
  );
}
