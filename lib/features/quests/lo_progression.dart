// One course's ordered objective (Mission) sequence and its per-objective
// activities, built from a quest outline. The shared data shape the next-Mission
// resolver (quest_progression_resolver.dart) consumes. Pure — no Matrix or
// network. Nothing is locked anymore; progression only ranks (#7186). Design:
// quests.instructions.md.

/// The XP a learner must earn toward a Mission for it to count as complete
/// (#9420), when the course sets no override. A teacher may override this per
/// course ("XP per Mission"). A hand-set lever: roughly one or two solid
/// activity sessions plus some practice, tuned by observation.
const int kDefaultXpToCompleteObjective = 300;

/// The share of a session's XP each sparkle (orchestrator-awarded goal) adds
/// on top of it: a session that earned three sparkles counts for 1.3× its XP
/// toward the Mission (#9439, the "minor goal multiplier"). Goals guide the
/// conversation and reward it a little; the XP is what fills the meter.
const double kSparkleXpBonus = 0.1;

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

  /// Each Mission's target vocabulary — the lower-cased lemmas of every
  /// suggested-vocab entry across its activities. Practice XP on one of these
  /// words counts toward the Mission (quests.instructions.md, "What fills a
  /// Mission"). Empty when the builder had no plans in hand.
  final Map<String, Set<String>> vocabLemmasByLo;

  /// The XP that completes a Mission in this course — the teacher's override,
  /// or [kDefaultXpToCompleteObjective].
  final int xpToComplete;

  const CourseLoOutline({
    required this.courseId,
    this.questId,
    required this.orderedLoIds,
    required this.activityIdsByLo,
    this.vocabLemmasByLo = const {},
    this.xpToComplete = kDefaultXpToCompleteObjective,
  });
}
