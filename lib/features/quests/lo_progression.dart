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
  /// The course's unique identity — its Matrix **room id** for a joined course.
  /// A per-course surface looks its own rollup up by this ([forCourse]).
  ///
  /// NOT the quest uuid: one quest can back several courses (launched into
  /// several rooms), so the quest uuid is shared and would collapse two courses
  /// that share a quest into one — the exact cross-contamination #8087 fixes.
  /// The room id is the thing that is one-per-course. (For the world map's
  /// scoped outline of a course the learner hasn't joined there is no room, so
  /// it falls back to [questId] — never a [forCourse] key, only banded.)
  final String courseId;

  /// The quest this course realizes (the quest-plans uuid). Shared across every
  /// course built from the same quest, so the world-map band can dedupe a quest
  /// the learner joined in two rooms instead of double-counting its gradient.
  final String questId;

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
    required this.questId,
    required this.orderedLoIds,
    required this.activityIdsByLo,
    this.starsToUnlock = kDefaultStarsToUnlockObjective,
    this.earnableByActivity = const {},
  });
}
