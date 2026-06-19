// The learning-objective progression gate: which objectives a learner has
// unlocked, given the stars they have earned. Pure logic so the gate is
// unit-testable without Matrix or the network. Design: quests.instructions.md.

/// The default number of stars (orchestrator-awarded activity goals) the learner
/// must earn in an objective to satisfy it and unlock the next one in the
/// sequence. A teacher may override this per course.
const int kDefaultStarsToUnlockObjective = 10;

/// One course's ordered objective sequence and the activities that satisfy each
/// objective, plus the star threshold that unlocks the next objective. Built
/// from a quest outline (the ordered sequence and its per-objective activities).
class CourseLoOutline {
  final List<String> orderedLoIds;
  final Map<String, Set<String>> activityIdsByLo;
  final int starsToUnlock;

  const CourseLoOutline({
    required this.orderedLoIds,
    required this.activityIdsByLo,
    this.starsToUnlock = kDefaultStarsToUnlockObjective,
  });
}

/// The resolved gate: the objectives a learner has unlocked, and the full set of
/// objectives that are subject to gating at all (those that appear in some
/// course sequence).
class LoProgressionGate {
  final Set<String> unlocked;
  final Set<String> gated;

  const LoProgressionGate({required this.unlocked, required this.gated});

  static const LoProgressionGate empty =
      LoProgressionGate(unlocked: {}, gated: {});

  /// A pin is locked when it carries at least one gated objective and none of
  /// its objectives is unlocked. A pin with no gated objective — a standalone or
  /// global activity outside any course sequence — is never locked, so the gate
  /// only dims content that sits behind real course progression.
  bool isPinLocked(Iterable<String> objectiveRefs) {
    if (!objectiveRefs.any(gated.contains)) return false;
    return !objectiveRefs.any(unlocked.contains);
  }
}

/// Resolve the gate from each course's outline and the learner's star total per
/// activity. An objective is unlocked when it is first in its sequence, or when
/// the objective before it has at least its course's star threshold, summed
/// across that objective's activities. An objective unlocked by any course wins:
/// the learner can reach it along whichever sequence opened it.
LoProgressionGate buildLoGate({
  required Iterable<CourseLoOutline> outlines,
  required Map<String, int> starsByActivity,
}) {
  final gated = <String>{};
  final unlocked = <String>{};

  for (final course in outlines) {
    final seq = course.orderedLoIds;
    gated.addAll(seq);

    int starsIn(String loId) {
      final acts = course.activityIdsByLo[loId];
      if (acts == null) return 0;
      var sum = 0;
      for (final activityId in acts) {
        sum += starsByActivity[activityId] ?? 0;
      }
      return sum;
    }

    for (var i = 0; i < seq.length; i++) {
      if (i == 0 || starsIn(seq[i - 1]) >= course.starsToUnlock) {
        unlocked.add(seq[i]);
      }
    }
  }

  return LoProgressionGate(unlocked: unlocked, gated: gated);
}
