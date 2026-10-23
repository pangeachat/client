import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// How many activities the course page's Activities row holds. A
/// shortlist, not the plan: the full ordered course plan is one tap away behind
/// "See full course plan". A hand-set lever, like the ranking weights it caps.
const int kSuggestedActivitiesCap = 5;

/// One activity of a course plan with every Mission it satisfies in that plan.
/// An activity can sit under more than one Mission, so the ranked row shows it
/// once and bands it on the union of its Missions.
class SuggestedActivity {
  final QuestActivity activity;
  final Set<String> missionIds;

  const SuggestedActivity({required this.activity, required this.missionIds});

  String get activityId => activity.activityId;
}

/// The course page's suggested activities: the course plan's activities scored
/// by the world map's Priority matrix ([pinScore]), with the sessions the
/// learner is already in and the activities they have finished dropped, capped
/// to [cap].
///
/// The same weighted score the map ranks pins by, so the two surfaces agree on
/// what matters — an open session others can be joined in outranks a pinged
/// one, which outranks whatever the course's next Mission points at
/// ([missionGradient]). Reusing [pinScore] is what keeps them from drifting as
/// the weights are tuned.
///
/// Four of the map's terms deliberately do not apply here:
///  * **ongoing** — an activity the learner already holds a role in is filtered
///    out entirely rather than scored. The course page suggests what to do
///    next; a session already under way is resumed from the Chats section.
///  * **completed** — a finished activity is likewise dropped rather than
///    demoted (#8901). The map keeps it as the learner's trail; a shortlist of
///    what to do next has no room for what is done, and the full plan behind
///    "See all" still shows it with its check. The one exception is a
///    coursemate's open session on it — still something to join, so it stays
///    and ranks as joinable.
///  * **multi_person_first_map** — world-map only. A course's activities were
///    hand-picked by its author, so a 3+ role one is part of the syllabus, not
///    a dead end (world-map.instructions.md, "Priority matrix").
///  * **dismissed** — the X on a large map card; this surface has no such card.
///
/// [recency][PinSignals.recency] is likewise left at 0: the course page reads
/// open sessions from the discovery cache, which carries no per-session start
/// time, and a continuously-decaying term would reorder the row under a learner
/// who is only reading it.
///
/// The course page's current-Mission row (#9437) passes [cap] null: the row is
/// the Mission's content, not a shortlist.
///
/// With [includeCompleted] the row is the Mission's whole queue (#9559):
/// nothing is dropped, and the order runs in tiers before the score —
///  1. a session the learner is in (with [includeOngoing]);
///  2. what they can play now: an unfinished activity they can start, or any
///     activity with a live session;
///  3. what they have finished, for another round;
///  4. what they can't start yet — more roles than the course can fill
///     ([canStart] false) and no live session to join.
/// So a finished activity still leads when nothing unfinished is playable.
List<SuggestedActivity> rankSuggestedActivities({
  required List<QuestObjectiveGroup> groups,
  required double Function(Set<String> missionRefs) missionGradient,
  required PinSignals Function(String activityId) signalsFor,
  int? cap = kSuggestedActivitiesCap,
  bool includeOngoing = false,
  bool includeCompleted = false,
  bool Function(QuestActivity activity)? canStart,
}) {
  final byActivity = <String, SuggestedActivity>{};
  for (final group in groups) {
    for (final activity in group.activities) {
      final existing = byActivity[activity.activityId];
      byActivity[activity.activityId] = SuggestedActivity(
        activity: activity,
        missionIds: {...?existing?.missionIds, group.objective.id},
      );
    }
  }

  // Each kept activity with its tier (the order above; with
  // [includeOngoing] alone, the learner's own sessions lead outright) and
  // its score within the tier.
  final scored = <(SuggestedActivity, int, double)>[];
  for (final suggestion in byActivity.values) {
    final signals = signalsFor(suggestion.activityId);
    // [includeOngoing]: the learner's own sessions stay in — continuing
    // what they started comes first (#9420).
    if (signals.state.isOngoing && !includeOngoing) continue;
    if (signals.isCompleted && !signals.state.isLive && !includeCompleted) {
      continue;
    }
    final tier = includeOngoing && signals.state.isOngoing
        ? 0
        : !includeCompleted || signals.state.isLive
        ? 1
        : !(canStart?.call(suggestion.activity) ?? true)
        ? 3
        : signals.isCompleted
        ? 2
        : 1;
    final plan = suggestion.activity.plan;
    scored.add((
      suggestion,
      tier,
      pinScore(
        band: missionGradient(suggestion.missionIds),
        s: signals,
        ratingAverage: plan.ratingAverage,
        ratingCount: plan.ratingCount,
      ),
    ));
  }

  // activityId tiebreaker: List.sort is unstable, so equal-score activities
  // would otherwise swap places between rebuilds and the row would reshuffle
  // itself while the learner looks at it (the map hit this as #8136).
  scored.sort((a, b) {
    final byTier = a.$2.compareTo(b.$2);
    if (byTier != 0) return byTier;
    final byScore = b.$3.compareTo(a.$3);
    return byScore != 0 ? byScore : a.$1.activityId.compareTo(b.$1.activityId);
  });

  final kept = cap == null ? scored : scored.take(cap);
  return [for (final (suggestion, _, _) in kept) suggestion];
}
