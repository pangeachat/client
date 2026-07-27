import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';

/// Pure derivations the world map computes from the learner's Matrix rooms,
/// lifted out of the map widget so they sit beside the other map-data logic
/// ([world_map_ranking.dart]) and can be read / unit-tested without the widget.
/// The map widget caches their results on room sync rather than recomputing per
/// frame. See world-map.instructions.md.
///
/// Each `…Signals` / `…Completion` function is split into a thin Matrix-reading
/// shell ([deriveActivitySignals] / [getActivityCompletionStatuses]) that turns each session
/// room into a plain facts record, and a **pure reducer** ([reduceActivitySignals]
/// / [reduceCompletion]) over those records. The reducer carries the actual rule
/// (best-of fraction, the colour-state ladder, recency) and is unit-tested
/// directly; the shell just reads room state. `nowMs` is injected so recency is
/// deterministic in tests.

/// One activity-session room reduced to the facts the pin signals need, so the
/// per-room scan and the pure reduction can be tested apart from Matrix state.
/// `joinable` (a free role the user has not taken) and `holdsRole` are mutually
/// exclusive in practice, but the reducer does not rely on that.
class ActivitySessionFacts {
  final String activityId;
  final bool holdsRole;
  final int collectedGoals;
  final int totalGoals;
  final bool joinable;
  final int lastEventMs;

  /// How many roles the activity's plan still needs filled (0 once the roster
  /// is full). Only meaningful when [holdsRole] is true — it's what
  /// distinguishes Ongoing/Pending (>0, the chat hasn't started) from
  /// Ongoing/Active (0, the room is full) — the same "is the room full" check
  /// [joinable] already uses (`Room.numRemainingRoles`). See
  /// world-map.instructions.md ("Pin state").
  final int numRemainingRoles;

  /// Whether the learner's own role in this session is finished
  /// (`Room.hasCompletedRole`) — true once they've finished the activity,
  /// whether or not every star was collected and whether or not they've since
  /// archived it. A finished role is "done", never a live "resume it" state,
  /// even if [completedOwnGoals] is false (finished without a full star row).
  final bool ownRoleFinished;

  const ActivitySessionFacts({
    required this.activityId,
    required this.holdsRole,
    required this.collectedGoals,
    required this.totalGoals,
    required this.joinable,
    required this.lastEventMs,
    this.numRemainingRoles = 0,
    this.ownRoleFinished = false,
  });

  double? get fractionGoalsCompleted {
    if (!holdsRole) return null;
    if (totalGoals <= 0) return 0;
    return (collectedGoals / totalGoals).clamp(0.0, 1.0);
  }

  /// Whether the learner has finished all their own goals in this session (its
  /// star row is full). Such a session is "done" — not a live "jump back in".
  bool get completedOwnGoals => totalGoals > 0 && collectedGoals >= totalGoals;

  /// The live-session colour state: a free role the user can take → `joinable`;
  /// else a role the user holds in a session they have **not yet finished**
  /// (resume it) → Ongoing, split by whether the roster is full yet:
  /// [numRemainingRoles] `> 0` → `ongoingPending` (waiting for other
  /// participants, the chat hasn't started); `== 0` → `ongoingActive` (the room
  /// is full, the chat has started). A session whose own goals are already
  /// complete, OR whose own role is already finished ([ownRoleFinished] —
  /// covers finishing without collecting every star, then archiving), is not a
  /// live state, so it returns null and the view layers `inProgress` (the gold
  /// trail star) from the learner's stars — otherwise a completed/archived
  /// activity the learner still belongs to would read Ongoing forever and
  /// never show its progress. The `inProgress` / `available` states are not
  /// live-session facts. See world-map.instructions.md ("Pin state").
  ActivityPinState? get state => joinable
      ? ActivityPinState.joinable
      : (holdsRole && !ownRoleFinished && !completedOwnGoals)
      ? (numRemainingRoles > 0
            ? ActivityPinState.ongoingPending
            : ActivityPinState.ongoingActive)
      : null;
}

/// One activity-session room reduced to the facts the completion filter needs.
typedef ActivityCompletionFacts = ({
  String activityId,
  int totalGoals,
  int collectedGoals,
});

class WorldMapSignalUtils {
  /// Window over which an open session's recency decays linearly to 0.
  static const int _recencyWindowMs = 24 * 60 * 60 * 1000;

  /// The pure pin-signal rule over per-room [facts]: for each activity keep the
  /// best completion fraction (a role the user holds), the highest live-session
  /// colour state on the `joinable < joined` ladder (the `inProgress` /
  /// `available` states are layered on downstream from stars), and the recency of
  /// its newest open session (decaying linearly to 0 over [_recencyWindowMs] from
  /// [nowMs]).
  static Map<String, PinSignals> reduceActivitySignals(
    Iterable<ActivitySessionFacts> facts, {
    required Set<String> pingedActivityIds,
    required int nowMs,
  }) {
    final stateById = <String, ActivityPinState>{};
    final newestOpenMs = <String, int>{};
    final fractionById = <String, double>{};

    for (final f in facts) {
      final activityId = f.activityId;

      final currentFraction = fractionById[activityId] ?? 0;
      final fractionCompleted = f.fractionGoalsCompleted;
      if (fractionCompleted != null && fractionCompleted > currentFraction) {
        fractionById[activityId] = fractionCompleted;
      }

      final currentNewestMs = newestOpenMs[f.activityId] ?? 0;
      if (f.joinable && f.lastEventMs > currentNewestMs) {
        newestOpenMs[activityId] = f.lastEventMs;
      }

      // Live-session colour state: a free role the user hasn't taken → joinable;
      // else holding a role in an open session → joined.
      final state = f.state;
      if (state == null) continue;

      final currentState = stateById[f.activityId];
      if (currentState == null || state.index > currentState.index) {
        stateById[f.activityId] = state; // ladder order = enum index order
      }
    }

    return Map<String, PinSignals>.fromEntries(
      stateById.entries.map((s) {
        final state = s.value;
        final activityId = s.key;

        final ms = newestOpenMs[activityId];
        final age = ms == null ? _recencyWindowMs : nowMs - ms;
        final recency = (1.0 - age / _recencyWindowMs).clamp(0.0, 1.0);

        final signal = PinSignals(
          state: state,
          completionFraction: fractionById[activityId] ?? 0,
          pinged: pingedActivityIds.contains(activityId),
          recency: recency,
        );

        return MapEntry<String, PinSignals>(activityId, signal);
      }),
    );
  }

  /// The pure completion rule over per-room [facts]: an activity is `completed`
  /// once any of the user's sessions has all role goals collected, else
  /// `inProgress`; the highest status wins across sessions.
  static Map<String, MapCompletionFilter> reduceActivityCompletions(
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
}
