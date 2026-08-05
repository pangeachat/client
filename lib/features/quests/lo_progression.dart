// One course's ordered objective (Mission) sequence and its per-objective
// activities, built from a quest outline. The shared data shape the next-Mission
// resolver (quest_progression_resolver.dart) consumes. Pure — no Matrix or
// network. Nothing is locked anymore; progression only ranks (#7186). Design:
// quests.instructions.md.

/// The default number of stars (orchestrator-awarded activity goals) the learner
/// must earn in an objective to satisfy it and unlock the next one in the
/// sequence. A teacher may override this per course.
const int kDefaultStarsToUnlockObjective = 10;

/// One course's ordered objective sequence and the activities that satisfy each
/// objective, plus the star threshold that unlocks the next objective. Built
/// from a quest outline (the ordered sequence and its per-objective activities).
class CourseLoOutline {
  /// The key a per-course surface scopes its rollup by — the course ROOM id
  /// for joined courses, or the quest uuid for scoped/preview outlines that
  /// have no room. Identity, not decoration: Missions are a shared catalog
  /// reused across quests, so a resolution spanning several joined courses can
  /// hold the same Mission more than once — this is how a per-course surface
  /// finds ITS rollup instead of a cross-course blend. The room id (never the
  /// quest uuid) is what keeps two courses built from ONE quest distinct
  /// (#8087).
  final String courseId;

  /// The quest (course-plan) uuid this outline resolved from, when known. The
  /// second key: two courses of one quest carry distinct [courseId]s but the
  /// same [questId], which is how the world-map band counts the quest once
  /// instead of double-counting per room. Null for legacy callers that only
  /// have one id — dedupe then falls back to [courseId].
  final String? questId;

  final List<String> orderedLoIds;
  final Map<String, Set<String>> activityIdsByLo;
  final int starsToUnlock;

  /// Stars ONE player can earn per activity (ActivityPlanModel.earnableStars),
  /// keyed by activity id. Feeds the resolver's threshold clamp: an objective's
  /// effective threshold never exceeds the sum of earnable stars across its
  /// activities (quests.instructions.md). Empty when the builder had no plans
  /// in hand — the resolver then leaves the configured threshold unclamped.
  final Map<String, int> earnableByActivity;

  const CourseLoOutline({
    required this.courseId,
    this.questId,
    required this.orderedLoIds,
    required this.activityIdsByLo,
    this.starsToUnlock = kDefaultStarsToUnlockObjective,
    this.earnableByActivity = const {},
  });
}
