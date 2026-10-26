import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_discovery.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_signals.dart';

/// Whether the learner has a saved session of a map activity — the completed
/// stamp the map draws at its point (world-map.instructions.md, "Goal
/// Progress").
enum ActivityStarLevel {
  /// No saved session — the activity renders `available`.
  none,

  /// At least one saved session — the completed stamp.
  star,
}

/// Whether one of the learner's rooms proves they have **finished** an
/// activity — the per-room gate behind
/// [WorldMapClientExtension.hasAnyFinishedActivitySession], and so behind the
/// `multi_person_first_map` new-learner condition (#7999).
///
/// Membership join, not invite: an unaccepted invite is not a prior activity
/// (an invited room's stripped state carries no role assignments at all).
///
/// Finished means the learner's OWN role in the session is finished — they
/// ended it, whether or not they collected every star. [ownRoleArchived] is
/// checked too because "Continue" ([Room.continueActivity]) clears
/// `finished_at` to reopen a done session, while the auto-save's `archived_at`
/// stays: the archive is the durable record that they did finish it once, so
/// reopening a finished activity can't drop them back to new-learner and
/// re-sink every 3+ role pin.
bool countsAsFinishedActivitySession({
  required String? activityId,
  required Membership membership,
  required bool ownRoleFinished,
  required bool ownRoleArchived,
}) =>
    activityId != null &&
    membership == Membership.join &&
    (ownRoleFinished || ownRoleArchived);

extension WorldMapClientExtension on Client {
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

  /// True once the learner has **finished** at least one activity. Its negation,
  /// "no finished activity yet," is the new-learner condition for the
  /// multi-person deprioritize (#7435, narrowed by #7999 — the term used to
  /// clear on merely *being in* a session room, so a learner who opened one
  /// activity and went back to exploring immediately saw unstartable 3+ role
  /// pins). Cheap: one pass over `client.rooms`.
  bool get hasAnyFinishedActivitySession => rooms.any(
    (r) => countsAsFinishedActivitySession(
      activityId: r.activityId,
      membership: r.membership,
      ownRoleFinished: r.hasCompletedRole,
      ownRoleArchived: r.hasArchivedActivity,
    ),
  );

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
