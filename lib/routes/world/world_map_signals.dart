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
///
/// Each `…Signals` / `…Completion` function is split into a thin Matrix-reading
/// shell ([deriveActivitySignals] / [userCompletion]) that turns each session
/// room into a plain facts record, and a **pure reducer** ([reduceActivitySignals]
/// / [reduceCompletion]) over those records. The reducer carries the actual rule
/// (best-of fraction, the colour-state ladder, recency) and is unit-tested
/// directly; the shell just reads room state. `nowMs` is injected so recency is
/// deterministic in tests.

/// One activity-session room reduced to the facts the pin signals need, so the
/// per-room scan and the pure reduction can be tested apart from Matrix state.
/// `joinable` (a free role the user has not taken) and `holdsRole` are mutually
/// exclusive in practice, but the reducer does not rely on that.
typedef ActivitySessionFacts = ({
  String activityId,
  bool holdsRole,
  int collectedGoals,
  int totalGoals,
  bool joinable,
  int lastEventMs,
});

/// One activity-session room reduced to the facts the completion filter needs.
typedef ActivityCompletionFacts = ({
  String activityId,
  int totalGoals,
  int collectedGoals,
});

/// Window over which an open session's recency decays linearly to 0.
const int _recencyWindowMs = 24 * 60 * 60 * 1000;

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
({Map<String, PinSignals> signals, Map<String, int> stars})
deriveActivitySignals(Client client, {required Set<String> pingedActivityIds}) {
  final facts = <ActivitySessionFacts>[];
  for (final room in client.rooms) {
    final activityId = room.activityId;
    if (activityId == null) continue;
    // The learner's own progress in this session (a role they hold): stars =
    // collected goals; fraction = collected / the role's total goals.
    final role = room.ownRole;
    facts.add((
      activityId: activityId,
      holdsRole: role != null,
      collectedGoals: role != null ? room.ownCompletedGoals.length : 0,
      totalGoals: role?.allGoals.length ?? 0,
      // A free role the user hasn't taken → joinable (the open-session state).
      joinable: room.numRemainingRoles > 0 && room.ownRoleState == null,
      lastEventMs: room.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0,
    ));
  }
  return (
    signals: reduceActivitySignals(
      facts,
      pingedActivityIds: pingedActivityIds,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Per-activity stars come from the one shared computation, so the map's
    // progression gate and the activity start page can't drift (user_stars.dart).
    stars: userStarsByActivity(client),
  );
}

/// The pure pin-signal rule over per-room [facts]: for each activity keep the
/// best completion fraction (a role the user holds), the highest colour state on
/// the `unlocked < joinable` ladder, and the recency of its newest open session
/// (decaying linearly to 0 over [_recencyWindowMs] from [nowMs]).
Map<String, PinSignals> reduceActivitySignals(
  Iterable<ActivitySessionFacts> facts, {
  required Set<String> pingedActivityIds,
  required int nowMs,
}) {
  final stateById = <String, ActivityPinState>{};
  final newestOpenMs = <String, int>{};
  final fractionById = <String, double>{};
  for (final f in facts) {
    if (f.holdsRole) {
      final frac = f.totalGoals > 0
          ? (f.collectedGoals / f.totalGoals).clamp(0.0, 1.0)
          : 0.0;
      if (frac > (fractionById[f.activityId] ?? 0)) {
        fractionById[f.activityId] = frac;
      }
    }
    // Colour state: a free role the user hasn't taken → joinable; else holding a
    // role → unlocked (completion shows as the fill, not a separate state).
    ActivityPinState? state;
    if (f.joinable) {
      state = ActivityPinState.joinable;
      if (f.lastEventMs > (newestOpenMs[f.activityId] ?? 0)) {
        newestOpenMs[f.activityId] = f.lastEventMs;
      }
    } else if (f.holdsRole) {
      state = ActivityPinState.unlocked;
    }
    if (state == null) continue;
    final existing = stateById[f.activityId];
    if (existing == null || state.index > existing.index) {
      stateById[f.activityId] = state; // ladder order = enum index order
    }
  }

  final signals = <String, PinSignals>{};
  stateById.forEach((id, state) {
    final ms = newestOpenMs[id];
    final age = ms == null ? _recencyWindowMs : nowMs - ms;
    final recency = (1.0 - age / _recencyWindowMs).clamp(0.0, 1.0);
    signals[id] = PinSignals(
      state: state,
      completionFraction: fractionById[id] ?? 0,
      pinged: pingedActivityIds.contains(id),
      recency: recency,
    );
  });
  return signals;
}

/// Per-activity completion for the logged-in user, from their session rooms:
/// completed = all of the user's role goals collected; in-progress = a joined
/// session that isn't complete; absent → not started. Same Matrix source as
/// [deriveActivitySignals]; drives the completion filter.
Map<String, MapCompletionFilter> userCompletion(Client client) {
  final facts = <ActivityCompletionFacts>[];
  for (final room in client.rooms) {
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
  return reduceCompletion(facts);
}

/// The pure completion rule over per-room [facts]: an activity is `completed`
/// once any of the user's sessions has all role goals collected, else
/// `inProgress`; the highest status wins across sessions.
Map<String, MapCompletionFilter> reduceCompletion(
  Iterable<ActivityCompletionFacts> facts,
) {
  final m = <String, MapCompletionFilter>{};
  for (final f in facts) {
    final status = (f.totalGoals > 0 && f.collectedGoals >= f.totalGoals)
        ? MapCompletionFilter.completed
        : MapCompletionFilter.inProgress;
    final existing = m[f.activityId];
    if (existing == null || status.index > existing.index) {
      m[f.activityId] = status;
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
