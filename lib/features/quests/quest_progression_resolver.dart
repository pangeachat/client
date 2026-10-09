// The shared client-side next-Mission resolver. Nothing is locked, so the
// question is not "is this allowed?" but "where should the learner go next?" —
// resolved ONCE from data the client already holds and shared by every surface
// that preferences by progression (the world map's Priority matrix, the
// activity start page). Pure logic — no Matrix or network — so it stays
// unit-testable. Design: quests.instructions.md, world-map.instructions.md.

import 'package:fluffychat/features/quests/lo_progression.dart';

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

/// One Mission's XP rollup: the XP the learner has earned toward it — in
/// sessions of its activities and in practice of its vocabulary — against the
/// threshold that completes it (#9420).
class MissionProgress {
  final int xp;
  final int threshold;

  const MissionProgress({required this.xp, required this.threshold});

  /// A Mission is complete — one star — once its XP reaches the
  /// (teacher-overridable) threshold. See quests.instructions.md.
  bool get satisfied => xp >= threshold;

  /// How full the Mission's meter is. Surplus XP shows raw in the count (e.g.
  /// 340/300); only the bar clamps.
  double get fraction => threshold <= 0 ? 0 : (xp / threshold).clamp(0.0, 1.0);
}

/// A quest's star summary: [earned] is the number of its Missions the learner
/// has completed (a star is a completed Mission), [total] the number of
/// Missions that can be — so earned/total is the full plan's progress
/// fraction. See quests.instructions.md ("Star display on the course panel").
class QuestStarSummary {
  final int earned;
  final int total;

  const QuestStarSummary({required this.earned, required this.total});

  double get fraction => total <= 0 ? 0 : (earned / total).clamp(0.0, 1.0);
}

/// One in-scope quest: its ordered Mission sequence, the resolved anchor (the
/// Mission the learner most needs next), and a position lookup for the gradient.
class QuestProgress {
  /// The key a per-course surface looks itself up by
  /// ([ProgressionResolution.forCourse]) — the course ROOM id for joined
  /// courses, or the quest uuid for scoped/preview outlines with no room. Two
  /// courses built from one quest carry distinct room ids, which is what keeps
  /// their rollups from crossing (#8087).
  final String courseId;

  /// The quest (course-plan) uuid this entry resolved from. The second key:
  /// entries for two rooms of ONE quest share it, and [missionGradient] counts
  /// each quest once by grouping on it.
  final String questId;

  final List<String> orderedMissionIds;

  /// The anchor (next) Mission: the first Mission in order whose XP is below
  /// the threshold. Null when there is no next step — every scored Mission
  /// complete, or none scored at all.
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
  ///
  /// Holds only the quest's **scored** Missions — those the outline gives at
  /// least one activity. A Mission with no activities offers no stars and the
  /// panel doesn't render it at all (#7114), so counting it would break the
  /// doc's denominator invariant (#7663). [orderedMissionIds] still carries the
  /// full sequence, so gradient distances are unaffected.
  final Map<String, MissionProgress> rollup;

  const QuestProgress({
    required this.courseId,
    required this.questId,
    required this.orderedMissionIds,
    required this.anchorMissionId,
    required this.indexByMission,
    required this.rollup,
  });

  /// This quest's own next-Mission contribution for an activity carrying
  /// [refs]: 1.0 at the anchor Mission, decaying linearly to 0 over
  /// [kBandFalloffMissions] Missions further along, 0 for a Mission that is
  /// already satisfied or sits before the anchor. Unclamped — the caller caps
  /// it at [kBandCeiling], which is where the cross-quest sum saturates.
  double missionGradient(Set<String> refs) {
    final anchor = anchorMissionId;
    if (anchor == null) return 0;
    final anchorIdx = indexByMission[anchor];
    if (anchorIdx == null) return 0;
    var contribution = 0.0;
    for (final ref in refs) {
      final idx = indexByMission[ref];
      if (idx == null) continue; // ref not part of this quest
      // Satisfied -> ~0, judged against THIS quest's own rollup: a Mission
      // finished in one course must not silence it in another.
      if (rollup[ref]?.satisfied ?? false) continue;
      final distance = idx - anchorIdx;
      if (distance < 0) continue; // a Mission before the anchor
      final refContribution = 1.0 - distance / kBandFalloffMissions;
      if (refContribution > 0) contribution += refContribution;
    }
    return contribution;
  }

  /// This quest's star summary: completed Missions over scored Missions.
  ///
  /// Computed here, from [rollup], on purpose — callers do NOT pass a Mission
  /// list. When they did, the course panel filtered to Missions with activities
  /// while the header counted every LO in the quest, so hidden activity-less
  /// Missions inflated the denominator (#7663). One owner for "which Missions
  /// count" means a caller can no longer disagree with the panel.
  QuestStarSummary get starSummary => QuestStarSummary(
    earned: rollup.values.where((p) => p.satisfied).length,
    total: rollup.length,
  );

  /// The Mission a learner should work on now: the anchor's rollup, or null
  /// when there is no anchor (unresolved, or every Mission complete).
  MissionProgress? get anchorProgress =>
      anchorMissionId == null ? null : rollup[anchorMissionId!];
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

  /// [courseId]'s star summary, from that course's own rollup — never a
  /// cross-course blend. Null when the course isn't in scope (a preview, or
  /// before the resolution lands); the header then renders its muted empty bar
  /// rather than a denominator invented from default thresholds.
  QuestStarSummary? questStars(String? courseId) =>
      forCourse(courseId)?.starSummary;

  /// The learner's stars: every Mission complete in any in-scope quest, by
  /// Mission id — a Mission two courses share is one star, not two, since the
  /// star is the learner's competency and not a course's bookkeeping. The
  /// analytics bar's count (#9436). [inScope] narrows to the quests whose
  /// course passes it (the bar counts one language at a time).
  Set<String> completedMissionIds({bool Function(String courseId)? inScope}) =>
      {
        for (final quest in quests)
          if (inScope == null || inScope(quest.courseId))
            for (final entry in quest.rollup.entries)
              if (entry.value.satisfied) entry.key,
      };

  /// The next-Mission gradient (0..[kBandCeiling]) for an activity carrying
  /// [objectiveRefs]: 1.0 at a quest's anchor Mission, decaying linearly to 0
  /// over [kBandFalloffMissions] Missions further along, ~0 for an already
  /// satisfied Mission or a Mission before the anchor. Contributions SUM across
  /// every in-scope QUEST (so an activity advancing several quests' unfinished
  /// Missions ranks higher) and saturate at the ceiling — a quest joined in
  /// more than one course room contributes once, at its strongest per-room
  /// value, never once per room (#8087). Outside any quest the activity's refs
  /// match nothing and this is 0 — the consumer then ranks it on plain
  /// level/L2 fit. See world-map.instructions.md Priority matrix.
  double missionGradient(Iterable<String> objectiveRefs) {
    if (quests.isEmpty) return 0;
    final refs = objectiveRefs.toSet();
    if (refs.isEmpty) return 0;

    // Grouped by questId so two rooms of one quest can't double-count. MAX
    // (not first-wins) because the rooms can diverge via pins: a Mission
    // satisfied in room A may still be room B's genuine next step, so the
    // strongest signal stands — and max is order-independent, where [quests]
    // order (rebuild completion order) is not.
    final bestByQuest = <String, double>{};
    for (final quest in quests) {
      final contribution = quest.missionGradient(refs);
      final best = bestByQuest[quest.questId];
      if (best == null || contribution > best) {
        bestByQuest[quest.questId] = contribution;
      }
    }
    var total = 0.0;
    for (final contribution in bestByQuest.values) {
      total += contribution;
    }
    return total.clamp(0.0, kBandCeiling);
  }
}

/// Resolve progression from each in-scope quest's [outlines] and the learner's
/// XP per activity ([xpByActivity], sessions of it with the sparkle bonus
/// applied — `Client.userXpByActivity`) plus their standalone-practice XP per
/// lemma ([xpByLemma], `MissionXpCache`). Pure. In-scope quests are the
/// learner's joined courses by default, or whatever the world map's quest filter
/// selects — the caller decides which outlines to pass; this only resolves them.
ProgressionResolution resolveProgression({
  required Iterable<CourseLoOutline> outlines,
  required Map<String, int> xpByActivity,
  Map<String, int> xpByLemma = const {},
}) {
  // Resolved per outline, NOT unioned across them. A Mission's XP total is
  // only meaningful against the activity set it was summed over, and Missions
  // are a shared catalog: two joined courses commonly carry the same Mission
  // with different activities, so a global rollup would credit one course's
  // XP to the other's content and undo its activity pins (#7771). An activity
  // two courses genuinely share still counts in both — each outline lists it,
  // so nothing needs merging.
  final quests = <QuestProgress>[];

  for (final outline in outlines) {
    final seq = outline.orderedLoIds;
    if (seq.isEmpty) continue;

    final rollup = <String, MissionProgress>{};
    for (final missionId in seq) {
      final activities = outline.activityIdsByLo[missionId] ?? const <String>{};
      // A Mission the outline gives NO activities offers no XP, and the panel
      // doesn't render it (#7114). Leave it out of the rollup entirely rather
      // than scoring it: counting it would add a Mission to the denominator
      // that no content backs (#7663).
      if (activities.isEmpty) continue;

      // Session XP (sparkle bonus already applied) across the Mission's
      // activities, plus practice XP on its vocabulary. No ceiling clamp any
      // more: XP is unbounded, so every Mission with an activity is
      // completable from its content (quests.instructions.md, "What fills a
      // Mission").
      var xp = 0;
      for (final activityId in activities) {
        xp += xpByActivity[activityId] ?? 0;
      }
      for (final lemma
          in outline.vocabLemmasByLo[missionId] ?? const <String>{}) {
        xp += xpByLemma[lemma] ?? 0;
      }
      rollup[missionId] = MissionProgress(
        xp: xp,
        threshold: outline.xpToComplete,
      );
    }

    quests.add(
      QuestProgress(
        courseId: outline.courseId,
        // Legacy/scoped outlines carry no separate questId; falling back to
        // courseId gives each its own dedupe group — exactly the pre-#8087
        // behavior.
        questId: outline.questId ?? outline.courseId,
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
/// whose XP is below its threshold. Null once every scored Mission is
/// complete — a finished quest has no next step, and naming one anyway
/// pointed the learner back at work already done (#8997).
///
/// Missions absent from [rollup] are unscored — the outline gives them no
/// activities — so they are skipped. Anchoring one would point the learner at a
/// Mission with nothing to play and, being unsatisfiable, would pin the anchor
/// there permanently. Null when the quest has no scored Mission at all.
String? _anchorFor(List<String> seq, Map<String, MissionProgress> rollup) {
  for (final missionId in seq) {
    final progress = rollup[missionId];
    if (progress == null) continue;
    if (!progress.satisfied) return missionId;
  }
  return null;
}
