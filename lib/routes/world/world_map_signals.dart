import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/quests/user_stars.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';

/// Pure derivations the world map computes from the learner's Matrix rooms,
/// lifted out of the map widget so they sit beside the other map-data logic
/// ([world_map_ranking.dart]) and can be read / unit-tested without the widget.
/// The map widget caches their results on room sync rather than recomputing per
/// frame. See world-map.instructions.md.

/// Derive each activity's live [PinSignals] from the user's Matrix rooms: the
/// highest-wins colour state on the `locked < unlocked < joinable` ladder, a
/// 0..1 completion fraction (stars earned toward the activity's total), recency
/// for the newest open session, and the pinged flag. Also returns the learner's
/// star total per activity (max across their sessions of it) for the
/// progression gate.
///
/// State derives from sessions the client can see locally: the user's own
/// sessions give unlocked, and any visible session with a free role the user
/// isn't bound to gives joinable. Open sessions by strangers are not in
/// `client.rooms`, so map-wide open-session discovery needs a backend endpoint
/// (see world-map.instructions.md). `locked` is layered on at render time from
/// the progression gate (quests.instructions.md): it depends on the pin's
/// objective refs, which aren't in room state, so it can't be resolved here.
({Map<String, PinSignals> signals, Map<String, int> stars})
deriveActivitySignals(Client client, {required Set<String> pingedActivityIds}) {
  final stateById = <String, ActivityPinState>{};
  final newestOpenMs = <String, int>{};
  final fractionById = <String, double>{};
  for (final room in client.rooms) {
    final activityId = room.activityId;
    if (activityId == null) continue;
    // The learner's own progress in this session (a role they hold): stars =
    // collected goals; fraction = collected / the role's total goals. Keep the
    // best across multiple sessions of the same activity.
    final role = room.ownRole;
    if (role != null) {
      final collected = room.ownCompletedGoals.length;
      final total = role.allGoals.length;
      final frac = total > 0 ? (collected / total).clamp(0.0, 1.0) : 0.0;
      if (frac > (fractionById[activityId] ?? 0)) {
        fractionById[activityId] = frac;
      }
    }
    // Colour state: a free role the user hasn't taken → joinable; else holding a
    // role → unlocked (completion shows as the fill, not a separate state).
    ActivityPinState? state;
    if (room.numRemainingRoles > 0 && room.ownRoleState == null) {
      state = ActivityPinState.joinable;
      final ms = room.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      if (ms > (newestOpenMs[activityId] ?? 0)) newestOpenMs[activityId] = ms;
    } else if (role != null) {
      state = ActivityPinState.unlocked;
    }
    if (state == null) continue;
    final existing = stateById[activityId];
    if (existing == null || state.index > existing.index) {
      stateById[activityId] = state; // ladder order = enum index order
    }
  }

  const windowMs = 24 * 60 * 60 * 1000; // recency decays to 0 over a day
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final signals = <String, PinSignals>{};
  stateById.forEach((id, state) {
    final ms = newestOpenMs[id];
    final age = ms == null ? windowMs : nowMs - ms;
    final recency = (1.0 - age / windowMs).clamp(0.0, 1.0);
    signals[id] = PinSignals(
      state: state,
      completionFraction: fractionById[id] ?? 0,
      pinged: pingedActivityIds.contains(id),
      recency: recency,
    );
  });
  // Per-activity stars come from the one shared computation, so the map's
  // progression gate and the activity start page can't drift (see user_stars.dart).
  return (signals: signals, stars: userStarsByActivity(client));
}

/// Per-activity completion for the logged-in user, from their session rooms:
/// completed = all of the user's role goals collected; in-progress = a joined
/// session that isn't complete; absent → not started. Same Matrix source as
/// [deriveActivitySignals]; drives the completion filter.
Map<String, MapCompletionFilter> userCompletion(Client client) {
  final m = <String, MapCompletionFilter>{};
  for (final room in client.rooms) {
    final activityId = room.activityId;
    if (activityId == null) continue;
    final role = room.ownRole;
    if (role == null) continue;
    final total = role.allGoals.length;
    final collected = room.ownCompletedGoals.length;
    final status = (total > 0 && collected >= total)
        ? MapCompletionFilter.completed
        : MapCompletionFilter.inProgress;
    final existing = m[activityId];
    if (existing == null || status.index > existing.index) {
      m[activityId] = status;
    }
  }
  return m;
}

/// CEFR levels at or below [level] — the personalized default band (attainable
/// + comfortable). Null level → all levels (no CEFR narrowing).
Set<LanguageLevelTypeEnum> bandAtOrBelow(LanguageLevelTypeEnum? level) {
  if (level == null) return LanguageLevelTypeEnum.values.toSet();
  return LanguageLevelTypeEnum.values
      .where((l) => l.storageInt <= level.storageInt)
      .toSet();
}
