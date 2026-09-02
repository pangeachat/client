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
/// learner is already in dropped, capped to [cap].
///
/// The same weighted score the map ranks pins by, so the two surfaces agree on
/// what matters — an open session others can be joined in outranks a pinged
/// one, which outranks whatever the course's next Mission points at
/// ([missionGradient]), which outranks an activity already finished. Reusing
/// [pinScore] is what keeps them from drifting as the weights are tuned.
///
/// Three of the map's terms deliberately do not apply here:
///  * **ongoing** — an activity the learner already holds a role in is filtered
///    out entirely rather than scored. The course page suggests what to do
///    next; a session already under way is resumed from the Chats section.
///  * **multi_person_first_map** — world-map only. A course's activities were
///    hand-picked by its author, so a 3+ role one is part of the syllabus, not
///    a dead end (world-map.instructions.md, "Priority matrix").
///  * **dismissed** — the X on a large map card; this surface has no such card.
///
/// [recency][PinSignals.recency] is likewise left at 0: the course page reads
/// open sessions from the discovery cache, which carries no per-session start
/// time, and a continuously-decaying term would reorder the row under a learner
/// who is only reading it.
List<SuggestedActivity> rankSuggestedActivities({
  required List<QuestObjectiveGroup> groups,
  required double Function(Set<String> missionRefs) missionGradient,
  required PinSignals Function(String activityId) signalsFor,
  int cap = kSuggestedActivitiesCap,
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

  final scored = <(SuggestedActivity, double)>[];
  for (final suggestion in byActivity.values) {
    final signals = signalsFor(suggestion.activityId);
    if (signals.state.isOngoing) continue;
    final plan = suggestion.activity.plan;
    scored.add((
      suggestion,
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
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : a.$1.activityId.compareTo(b.$1.activityId);
  });

  return [for (final (suggestion, _) in scored.take(cap)) suggestion];
}
