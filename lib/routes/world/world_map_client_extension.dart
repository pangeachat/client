import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_discovery.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_awarded_goals.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_signals.dart';

/// The learner's completion tier for a map activity (world-map.instructions.md,
/// "Goal Progress"). A gold star appears **only** once a full role is done —
/// partial progress is never shown on a pin.
enum ActivityStarLevel {
  /// No role fully completed — not a star pin (the activity renders `available`).
  none,

  /// All goals of at least one role completed in some session — a gold star.
  star,

  /// Every role's goals completed across the learner's attempts — a super star.
  superStar,
}

/// The star tier from the learner's [completedRoles] on an activity and its
/// full [allRoleIds]: `none` (no full role → not a star), `star` (≥1 role),
/// `superStar` (every role). Falls back to `star` only when the total role set
/// is unknown (no hydrated plan AND the card didn't project its roles), since
/// "all roles" then can't be proven. Pure — fed by
/// [WorldMapClientExtension.completedRolesByActivity] (per-role completion) and
/// [WorldMapClientExtension.roleIdsByActivity] (the room-derived total role set).
ActivityStarLevel starLevelFor(
  Set<String> completedRoles,
  Iterable<String> allRoleIds,
) {
  if (completedRoles.isEmpty) return ActivityStarLevel.none;
  if (allRoleIds.isNotEmpty && completedRoles.containsAll(allRoleIds)) {
    return ActivityStarLevel.superStar;
  }
  return ActivityStarLevel.star;
}

/// One joined session room's own-role award facts: the role the learner held
/// there and that room's cumulative orchestrator awards. The per-attempt input
/// [starLevelForCard] joins against a pin's thin goals.
typedef OwnRoleAwards = ({String roleId, OrchestratorAwardedGoals awards});

/// The learner's star tier for [card], resolved hydration-free against the
/// pin's **current** thin goals: a role is complete when every card goal
/// listing it is awarded — matched on `goal_slug` first, then the legacy goal
/// id ([OrchestratorAwardedGoals.isGoalCompletedForRole]) — with awards
/// unioned across the learner's attempts ([ownAwards]); Ava's Pins-v6 note's
/// "through all their attempts". (Star *counts* stay best-single-session per
/// quests.instructions.md — the tier and the numerals answer different
/// questions.) Judging against the card rather than each room's frozen plan
/// snapshot means an owner edit re-derives completion: adding a goal demotes
/// an earned star/super star until the new goal too is earned (accepted
/// 2026-07-18 — world-map.instructions.md, "Goal Progress"). Returns null when
/// the card carries no thin goals (an older choreo) — callers fall back to the
/// room-derived [starLevelFor] path.
ActivityStarLevel? starLevelForCard(
  QuestActivityCard card,
  List<OwnRoleAwards> ownAwards,
) {
  if (card.goals.isEmpty) return null;

  final goalsByRole = <String, List<ActivityCardGoal>>{};
  for (final g in card.goals) {
    for (final r in g.roleIds) {
      (goalsByRole[r] ??= []).add(g);
    }
  }
  // The authoritative role set: the card's thin roles, else the goals' roles.
  // A role the card lists but no goal covers can never read complete, which
  // conservatively blocks the super star (matches the room path: a zero-goal
  // role is never "completed").
  final allRoles = card.roleIds.isNotEmpty
      ? card.roleIds.toSet()
      : goalsByRole.keys.toSet();

  bool roleDone(String roleId) {
    final roleGoals = goalsByRole[roleId];
    if (roleGoals == null || roleGoals.isEmpty) return false;
    return roleGoals.every(
      (g) => ownAwards.any(
        (a) =>
            a.roleId == roleId &&
            a.awards.isGoalCompletedForRole(
              roleId,
              g.id ?? '',
              goalSlug: g.goalSlug,
            ),
      ),
    );
  }

  return starLevelFor(allRoles.where(roleDone).toSet(), allRoles);
}

extension WorldMapClientExtension on Client {
  /// The learner's completed role-ids per activity across their joined sessions,
  /// built in ONE pass over `rooms` — the precomputed source for [starLevelFor]
  /// so the map resolves each pin's star tier without rescanning rooms per pin
  /// (mirrors the precomputed `_userStars` in the pins manager). A role counts
  /// as done when the learner completed all its goals in one of their own joined
  /// sessions ([Room.hasCompletedOwnGoals]).
  Map<String, Set<String>> get completedRolesByActivity {
    final result = <String, Set<String>>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null) continue;
      if (room.membership != Membership.join) continue;
      final roleId = room.ownRole?.id;
      if (roleId == null) continue;
      if (!room.hasCompletedOwnGoals) continue;
      (result[activityId] ??= <String>{}).add(roleId);
    }
    return result;
  }

  /// The full role-id set per activity, unioned from the hydrated plan
  /// (`activityPlan.roles`) on the learner's joined session rooms — the
  /// room-derived "all roles" for [starLevelFor], so the super-star no longer
  /// depends on the thin bbox card projecting `roles` (which it may omit). Built
  /// in ONE pass over `rooms`, mirroring [completedRolesByActivity].
  Map<String, Set<String>> get roleIdsByActivity {
    final result = <String, Set<String>>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null) continue;
      if (room.membership != Membership.join) continue;
      final roleIds = room.activityPlan?.roles.keys;
      if (roleIds == null) continue;
      (result[activityId] ??= <String>{}).addAll(roleIds);
    }
    return result;
  }

  /// The learner's own-role award facts per activity across their joined
  /// session rooms, built in ONE pass over `rooms` (the same discipline as
  /// [completedRolesByActivity]) — the input [starLevelForCard] joins against
  /// each pin's thin goals. Every room where the learner held a role
  /// contributes an entry; the resolver unions awards per goal across them.
  Map<String, List<OwnRoleAwards>> get ownRoleAwardsByActivity {
    final result = <String, List<OwnRoleAwards>>{};
    for (final room in rooms) {
      final activityId = room.activityId;
      if (activityId == null) continue;
      if (room.membership != Membership.join) continue;
      final roleId = room.ownRole?.id;
      if (roleId == null) continue;
      (result[activityId] ??= []).add((
        roleId: roleId,
        awards: room.orchestratorAwardedGoals,
      ));
    }
    return result;
  }

  /// The learner's [ActivityStarLevel] for a single [activityId] — the
  /// convenience over [completedRolesByActivity]/[roleIdsByActivity]/
  /// [starLevelFor]. Prefer the precomputed maps in a per-pin loop; this rescans
  /// rooms on each call. When [allRoleIds] is omitted the room-derived total set
  /// is used, so the super-star stays reachable without the bbox card's roles.
  ActivityStarLevel activityStarLevel(
    String activityId, {
    Iterable<String>? allRoleIds,
  }) => starLevelFor(
    completedRolesByActivity[activityId] ?? const {},
    allRoleIds ?? roleIdsByActivity[activityId] ?? const {},
  );

  /// The learner's OWN session room for [activityId] — a room they have *joined*
  /// (membership join), whether or not they have confirmed a role. Prefers a
  /// room where they hold a role, then the most recently active. This is the
  /// inverse of [bestJoinableActivityInstance] (which finds a free seat in
  /// *another* learner's open session): here we resolve "my started/joined
  /// session" so a map-pin tap reopens it (binding the overlay via `roomid=`)
  /// instead of spawning a fresh instance (#7257).
  Room? activeActivityInstance(String activityId) {
    Room? best;
    var bestHasRole = false;
    for (final r in rooms) {
      if (r.activityId != activityId) continue;
      if (r.membership != Membership.join) continue;

      final ownRole = r.ownRoleState;
      final hasRole = ownRole != null;
      if (ownRole != null && ownRole.isFinished) continue;

      final ms = r.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      final bestMs =
          best?.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      if (best == null ||
          (hasRole && !bestHasRole) ||
          (hasRole == bestHasRole && ms > bestMs)) {
        best = r;
        bestHasRole = hasRole;
      }
    }
    return best;
  }

  Room? bestJoinableActivityInstance(String activityId) {
    Room? best;
    for (final r in rooms) {
      if (r.activityId != activityId) continue;
      // Joined rooms only: an invited room's stripped state carries no role
      // assignments, so its seat data is phantoms — invited sessions are
      // previewed by discovery instead (#7488).
      if (r.membership != Membership.join) continue;
      if (!(r.numRemainingRoles > 0 && r.ownRoleState == null)) continue;
      final ms = r.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      final bestMs =
          best?.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      if (best == null || ms > bestMs) best = r;
    }
    return best;
  }

  /// The learner's joined course spaces (a space they belong to that carries a
  /// course plan) — the source set for the objective cache + relevance banding.
  /// Aliases the shared [ActivitySessionDiscovery.joinedCourseSpaces] so the map
  /// and the activity start page share one definition.
  List<Room> get joinedCourseRooms => joinedCourseSpaces;

  /// True once the learner is in **any** activity-session room — i.e. they have
  /// started, joined, or finished at least one activity (every such path leaves
  /// them a member of a `p.activity.session:<id>` room). Its negation, "no first
  /// activity yet," is the new-learner condition for the multi-person
  /// deprioritize (#7435). Cheap: one pass over `client.rooms`.
  /// Membership join, not invite: an unaccepted invite is not a prior activity.
  bool get hasAnyActivitySession =>
      rooms.any((r) => r.activityId != null && r.membership == Membership.join);

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
        // Joined rooms only. An invited room's stripped state carries no
        // pangea.activity_roles, so a locally-derived fact would report every
        // seat free — a phantom joinable that skips the finished/full/presence
        // gates. Invited sessions flow through the discovery preview instead
        // (world-map.instructions.md, "Discovering joinable sessions"; #7488).
        if (r.membership != Membership.join) return null;

        final role = r.ownRole;
        return ActivitySessionFacts(
          activityId: activityId,
          holdsRole: role != null,
          collectedGoals: role != null ? r.ownCompletedGoals.length : 0,
          totalGoals: role?.allGoals.length ?? 0,
          // A free role the user hasn't taken → joinable (the open-session state).
          joinable: r.numRemainingRoles > 0 && r.ownRoleState == null,
          lastEventMs: r.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0,
          // Distinguishes ongoingPending (>0, chat hasn't started) from
          // ongoingActive (0, roster full) when holdsRole is true.
          numRemainingRoles: r.numRemainingRoles,
          // A finished own role (even one not fully starred, or archived) is
          // never a live "resume it" state.
          ownRoleFinished: r.hasCompletedRole,
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
  ///
  /// [extraFacts] are sessions the client can see only by discovery, not from
  /// its own rooms — a coursemate's open session in a joined course, previewed
  /// via `room_preview` (world-map.instructions.md, "Discovering joinable
  /// sessions"). They run through the same reducer as owned rooms, so a session
  /// the learner is genuinely in (`joined`) still wins state over a discovered
  /// `joinable` for the same activity.
  Map<String, PinSignals> deriveActivitySignals({
    required Set<String> pingedActivityIds,
    List<ActivitySessionFacts> extraFacts = const [],
  }) => WorldMapSignalUtils.reduceActivitySignals(
    [..._activitySessionFacts, ...extraFacts],
    pingedActivityIds: pingedActivityIds,
    nowMs: DateTime.now().millisecondsSinceEpoch,
  );
}
