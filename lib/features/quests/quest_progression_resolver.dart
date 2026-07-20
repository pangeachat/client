// The shared client-side next-Mission resolver. Nothing is locked, so the
// question is not "is this allowed?" but "where should the learner go next?" —
// resolved ONCE from data the client already holds and shared by every surface
// that preferences by progression (the world map's Priority matrix, the
// activity start page). Pure logic — no Matrix or network — so it stays
// unit-testable. Design: quests.instructions.md, world-map.instructions.md.

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';

/// How far along a quest the next-Mission gradient reaches before decaying to
/// zero. The anchor Mission scores 1.0; each Mission further along loses
/// 1/[kBandFalloffMissions], hitting 0 this many Missions past the anchor. A
/// hand-set lever, tuned by observation (world-map.instructions.md: "weights are
/// levers, learned later").
const int kBandFalloffMissions = 3;

/// The relevance-band ceiling: the next-Mission gradient is summed across the
/// learner's in-scope quests and saturates here, keeping it under the heavier
/// `joinable` score term (world-map.instructions.md Priority matrix).
const double kBandCeiling = 2.0;

/// One Mission's star rollup: the stars the learner has earned toward it
/// (summed across its activities) against the threshold that satisfies it.
class MissionProgress {
  final int stars;
  final int threshold;

  const MissionProgress({required this.stars, required this.threshold});

  /// A star is one orchestrator-awarded activity goal; a Mission is satisfied
  /// once its star total reaches the (teacher-overridable) threshold.
  bool get satisfied => stars >= threshold;

  /// Stars capped at the threshold — the Mission's contribution to a quest's
  /// star total, so an over-practiced Mission can't inflate quest progress.
  /// The per-Mission display shows the raw [stars] (surplus effort shows,
  /// e.g. 12/7); only the quest-level sum caps. See quests.instructions.md.
  int get cappedStars => stars > threshold ? threshold : stars;
}

/// A quest's star display summary: [earned] sums each Mission's stars capped
/// at its threshold; [total] sums the thresholds — so earned/total is the
/// quest header's progress fraction. See quests.instructions.md ("Star display
/// on the course panel").
class QuestStarSummary {
  final int earned;
  final int total;

  const QuestStarSummary({required this.earned, required this.total});

  double get fraction => total <= 0 ? 0 : (earned / total).clamp(0.0, 1.0);
}

/// One in-scope quest: its ordered Mission sequence, the resolved anchor (the
/// Mission the learner most needs next), and a position lookup for the gradient.
class QuestProgress {
  /// The course-plan uuid this quest was resolved from — the key a per-course
  /// surface looks itself up by ([ProgressionResolution.forCourse]).
  final String courseId;

  final List<String> orderedMissionIds;

  /// The anchor (next) Mission: the first Mission in order whose star total is
  /// below the threshold; once every Mission is satisfied, the lowest-star
  /// Mission (so a finished quest keeps pointing at the weakest area). Null only
  /// when the sequence is empty.
  final String? anchorMissionId;

  final Map<String, int> indexByMission;

  /// This quest's OWN per-Mission rollup, scoped to the activities its outline
  /// lists — which, for a course that pins, is the pinned set.
  ///
  /// Scoping is the whole point. Missions are a shared catalog reused across
  /// quests, so two joined courses routinely carry the same Mission with
  /// different activities; rolling them up globally would clamp this course's
  /// effective threshold against another course's content and credit its stars
  /// (#7771). Where two courses genuinely list the SAME activity, each still
  /// counts it — that case needs no union, since both outlines carry it.
  final Map<String, MissionProgress> rollup;

  const QuestProgress({
    required this.courseId,
    required this.orderedMissionIds,
    required this.anchorMissionId,
    required this.indexByMission,
    required this.rollup,
  });
}

/// The shared resolution: one [QuestProgress] per in-scope quest, each with its
/// own Mission rollup. Consumers read [missionGradient] to score an activity's
/// relevance toward the learner's frontier, or [forCourse] to read a single
/// course's star numbers.
class ProgressionResolution {
  /// One entry per in-scope quest, each carrying its resolved anchor and its
  /// own per-Mission rollup. There is deliberately no cross-quest rollup: a
  /// star total only means something within the course whose activities it was
  /// summed over (see [QuestProgress.rollup]).
  final List<QuestProgress> quests;

  const ProgressionResolution({required this.quests});

  /// Fail-soft: a surface that asks before the resolver is built (or a learner
  /// with no in-scope quest) gets a neutral band, never a wall.
  static const ProgressionResolution empty = ProgressionResolution(quests: []);

  /// This course's resolved quest, or null when it isn't in scope (not joined,
  /// or the resolution hasn't landed). Callers fail soft on null rather than
  /// falling back to another course's numbers.
  QuestProgress? forCourse(String? courseId) {
    if (courseId == null) return null;
    for (final quest in quests) {
      if (quest.courseId == courseId) return quest;
    }
    return null;
  }

  /// The star summary for [courseId] given its ordered [missionIds]:
  /// per-Mission stars capped at each threshold, summed, over the summed
  /// thresholds. Read from that course's own rollup — never a cross-course
  /// blend. A Mission its rollup doesn't know (course not in scope, or the
  /// resolution hasn't landed) contributes its default threshold and zero
  /// stars, so a partially-resolved panel still shows a stable denominator.
  QuestStarSummary questStars(String? courseId, Iterable<String> missionIds) {
    final scoped =
        forCourse(courseId)?.rollup ?? const <String, MissionProgress>{};
    var earned = 0;
    var total = 0;
    for (final id in missionIds) {
      final progress = scoped[id];
      earned += progress?.cappedStars ?? 0;
      total += progress?.threshold ?? kDefaultStarsToUnlockObjective;
    }
    return QuestStarSummary(earned: earned, total: total);
  }

  /// The next-Mission gradient (0..[kBandCeiling]) for an activity carrying
  /// [objectiveRefs]: 1.0 at a quest's anchor Mission, decaying linearly to 0
  /// over [kBandFalloffMissions] Missions further along, ~0 for an already
  /// satisfied Mission or a Mission before the anchor. Contributions SUM across
  /// every in-scope quest (so an activity advancing several quests' unfinished
  /// Missions ranks higher) and saturate at the ceiling. Outside any quest the
  /// activity's refs match nothing and this is 0 — the consumer then ranks it on
  /// plain level/L2 fit. See world-map.instructions.md Priority matrix.
  double missionGradient(Iterable<String> objectiveRefs) {
    if (quests.isEmpty) return 0;
    final refs = objectiveRefs.toSet();
    if (refs.isEmpty) return 0;

    var total = 0.0;
    for (final quest in quests) {
      final anchor = quest.anchorMissionId;
      if (anchor == null) continue;
      final anchorIdx = quest.indexByMission[anchor];
      if (anchorIdx == null) continue;
      for (final ref in refs) {
        final idx = quest.indexByMission[ref];
        if (idx == null) continue; // ref not part of this quest
        // Satisfied → ~0, judged against THIS quest's own rollup: a Mission
        // finished in one course must not silence it in another.
        if (quest.rollup[ref]?.satisfied ?? false) continue;
        final distance = idx - anchorIdx;
        if (distance < 0) continue; // a Mission before the anchor
        final contribution = 1.0 - distance / kBandFalloffMissions;
        if (contribution > 0) total += contribution;
      }
    }
    return total.clamp(0.0, kBandCeiling);
  }

  /// Resolve the learner's shared joined-course progression — the SAME inputs and
  /// resolver as the world map, so the star numbers can never disagree
  /// (quests.instructions.md). Called by both the header's [CourseProgressBar] and
  /// the objective list's per-Mission chips; identical cached inputs (the quest
  /// outline cache + `client.userStarsByActivity`) mean the two can't drift, so a
  /// second resolve is safe rather than a re-derivation risk.
  static Future<ProgressionResolution> resolveJoinedProgression(
    Client client,
  ) async {
    final cache = JoinedObjectiveCache();
    await cache.rebuildFromJoinedCourses(
      client,
      onError: (uuid, e, s) => ErrorHandler.logError(
        e: e,
        s: s,
        m: 'course progression failed to resolve',
        data: {'courseUuid': uuid},
      ),
    );
    return cache.resolution(client.userStarsByActivity);
  }
}

/// Resolve progression from each in-scope quest's [outlines] and the learner's
/// star total per activity ([starsByActivity]). Pure. In-scope quests are the
/// learner's joined courses by default, or whatever the world map's quest filter
/// selects — the caller decides which outlines to pass; this only resolves them.
ProgressionResolution resolveProgression({
  required Iterable<CourseLoOutline> outlines,
  required Map<String, int> starsByActivity,
}) {
  // Resolved per outline, NOT unioned across them. A Mission's star total is
  // only meaningful against the activity set it was summed over, and Missions
  // are a shared catalog: two joined courses commonly carry the same Mission
  // with different activities, so a global rollup would clamp one course's
  // threshold against the other's content and credit its stars (#7771). An
  // activity two courses genuinely share still counts in both — each outline
  // lists it, so nothing needs merging.
  final quests = <QuestProgress>[];

  for (final outline in outlines) {
    final seq = outline.orderedLoIds;
    if (seq.isEmpty) continue;

    final rollup = <String, MissionProgress>{};
    for (final missionId in seq) {
      var stars = 0;
      var earnableCeiling = 0;
      for (final activityId
          in outline.activityIdsByLo[missionId] ?? const <String>{}) {
        stars += starsByActivity[activityId] ?? 0;
        earnableCeiling += outline.earnableByActivity[activityId] ?? 0;
      }
      final configured = outline.starsToUnlock;
      // Effective threshold: the configured stars-to-unlock clamped to the sum
      // of earnable stars across the Mission's activities, so a Mission is
      // always satisfiable from its content and displays never advertise stars
      // the learner cannot earn (org quests doc invariant; #7663). A ceiling of
      // 0 means no goal data reached the outline (degraded/legacy plans) —
      // leave the configured threshold rather than marking it satisfied at 0.
      rollup[missionId] = MissionProgress(
        stars: stars,
        threshold: earnableCeiling > 0 && earnableCeiling < configured
            ? earnableCeiling
            : configured,
      );
    }

    quests.add(
      QuestProgress(
        courseId: outline.courseId,
        orderedMissionIds: seq,
        anchorMissionId: _anchorFor(seq, rollup),
        indexByMission: {for (var i = 0; i < seq.length; i++) seq[i]: i},
        rollup: rollup,
      ),
    );
  }

  return ProgressionResolution(quests: quests);
}

/// The anchor (next) Mission for one quest's ordered [seq]: the first Mission
/// whose rollup is below threshold; once all are satisfied, the lowest-star
/// Mission, tie-broken by earliest quest order (deterministic, so the anchor
/// does not flicker between equal-star frames).
String? _anchorFor(List<String> seq, Map<String, MissionProgress> rollup) {
  for (final missionId in seq) {
    if (!(rollup[missionId]?.satisfied ?? false)) return missionId;
  }
  String? lowest;
  int? lowestStars;
  for (final missionId in seq) {
    final stars = rollup[missionId]?.stars ?? 0;
    if (lowestStars == null || stars < lowestStars) {
      lowest = missionId;
      lowestStars = stars;
    }
  }
  return lowest;
}
