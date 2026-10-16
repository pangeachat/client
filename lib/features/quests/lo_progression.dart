// One course's ordered objective (Mission) sequence and its per-objective
// activities, built from a quest outline. The shared data shape the next-Mission
// resolver (quest_progression_resolver.dart) consumes. Pure — no Matrix or
// network. Nothing is locked anymore; progression only ranks (#7186). Design:
// quests.instructions.md.

/// The XP a learner must earn under a Mission for it to count as complete
/// (#9420) when the course sets no override: the Standard preset, sized from
/// measured sessions as two activities with their goals at typical assistance
/// use. The instructor picks a preset or a custom value in the admin dashboard
/// (org quests-and-learning-objectives doc, "XP per objective").
const int kDefaultXpToCompleteObjective = 1600;

/// What one awarded activity goal — a checkmark — pays into the session's
/// activity XP, flat. Goals guide the conversation and reward it; the XP is
/// what completes the Mission (org activities doc, "Activity XP").
const int kGoalXp = 100;

/// One course's ordered objective sequence and the activities that satisfy each
/// objective, plus the XP threshold that completes an objective. Built from a
/// quest outline (the ordered sequence and its per-objective activities).
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

  /// Each Mission's word list — every suggested word across its activities,
  /// lowercased. Practice on one of these words outside a session counts
  /// toward the Mission (#9420). Empty for a caller with no plans.
  final Map<String, Set<String>> lemmasByLo;

  /// The XP that completes a Mission in this course — the instructor's
  /// setting, or [kDefaultXpToCompleteObjective].
  final int xpToComplete;

  const CourseLoOutline({
    required this.courseId,
    this.questId,
    required this.orderedLoIds,
    required this.activityIdsByLo,
    this.lemmasByLo = const {},
    this.xpToComplete = kDefaultXpToCompleteObjective,
  });
}
