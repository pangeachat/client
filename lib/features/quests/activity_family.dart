// The activity "family": an original activity and every course-private copy a
// teacher made of it (Content Studio v2). A student's stars on any member of a
// family are credited to whichever member the course shows, so a swap, an
// edit, a hide or an undo never costs progress. Pure — no Matrix or network.
// Design: content-studio.instructions.md; the shared rules live in the v2
// contract and are pinned by the parity fixture
// (test/pangea/quests/fixtures/studio-family-parity.json).

/// One activity the course credits, with the ids of its whole family as the
/// listing returned them (`family_ids`: the root plus every copy, any course).
class ListedActivity {
  final String activityId;

  /// Every id in this activity's family. Empty or missing reads as just
  /// [activityId] (a library row with no copies).
  final List<String> familyIds;

  /// Whether the course shows this activity to students. A hidden or removed
  /// activity is still credited, but never wins the family's canonical id over
  /// a shown member.
  final bool shown;

  const ListedActivity({
    required this.activityId,
    this.familyIds = const [],
    this.shown = true,
  });
}

/// Maps every member of every family among [creditedInCourseOrder] to that
/// family's canonical id: its first shown member in course order, else its
/// first removed member. [creditedInCourseOrder] is each Can-Do's
/// `activity_ids` then its `removed_activity_ids`, then the activities of
/// `removed_missions`, in course order.
///
/// Families are grouped by overlap, not by a single id, so two listings that
/// each name part of a family (a copy of a copy) still resolve to one id.
Map<String, String> activityFamily(List<ListedActivity> creditedInCourseOrder) {
  final parent = <String, String>{};
  String find(String id) {
    var root = parent.putIfAbsent(id, () => id);
    while (root != parent[root]) {
      root = parent[root]!;
    }
    // Path compression.
    var cursor = id;
    while (parent[cursor] != root) {
      final next = parent[cursor]!;
      parent[cursor] = root;
      cursor = next;
    }
    return root;
  }

  void union(String a, String b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) parent[rootB] = rootA;
  }

  for (final item in creditedInCourseOrder) {
    find(item.activityId);
    for (final id in item.familyIds) {
      union(item.activityId, id);
    }
  }

  final canonicalByRoot = <String, String>{};
  // First shown member wins; pass 1 over shown, pass 2 fills families that
  // have none.
  for (final item in creditedInCourseOrder) {
    if (item.shown) {
      canonicalByRoot.putIfAbsent(find(item.activityId), () => item.activityId);
    }
  }
  for (final item in creditedInCourseOrder) {
    canonicalByRoot.putIfAbsent(find(item.activityId), () => item.activityId);
  }

  return {
    for (final id in parent.keys.toList()) id: canonicalByRoot[find(id)]!,
  };
}

/// Sums each member's value onto its family's canonical id. Members absent
/// from [family] are dropped: they are not credited by this course.
Map<String, num> creditByShown(
  Map<String, num> perMember,
  Map<String, String> family,
) {
  final out = <String, num>{};
  for (final entry in perMember.entries) {
    final canonical = family[entry.key];
    if (canonical == null) continue;
    out[canonical] = (out[canonical] ?? 0) + entry.value;
  }
  return out;
}

/// What a course credits to its Can-Dos: the family map plus which activity
/// ids each Can-Do (and the removed Can-Dos) own. Empty means "no course
/// copy": every reader then behaves exactly as before copies existed.
class CourseCredit {
  /// Member id -> canonical id ([activityFamily]).
  final Map<String, String> family;

  /// Per Can-Do: the activity ids it credits that students do not see — its
  /// `removed_activity_ids`. Shown ids come from the outline itself.
  final Map<String, List<String>> removedByLo;

  /// Every activity of the Can-Dos the teacher removed. Credited to the
  /// course total only.
  final Set<String> removedMissionActivityIds;

  /// The activities the course shows (every Can-Do's `activity_ids`).
  final Set<String> shownIds;

  const CourseCredit({
    this.family = const {},
    this.removedByLo = const {},
    this.removedMissionActivityIds = const {},
    this.shownIds = const {},
  });

  static const CourseCredit none = CourseCredit();

  bool get isEmpty => family.isEmpty;

  /// The canonical id [id] is credited to.
  String canonicalOf(String id) => family[id] ?? id;

  /// [perMember] (one value per activity, already reduced per member) summed
  /// onto canonical ids. A no-op without a course copy.
  ///
  /// The hook for XP: the per-Can-Do XP reader (client#9450) sums each
  /// member's sessions, then calls this.
  Map<String, num> creditedBy(Map<String, num> perMember) =>
      isEmpty ? perMember : creditByShown(perMember, family);

  /// The stars the course credits to [activityId] out of [perMember] (best
  /// session per activity): what a card for a shown activity displays. A
  /// member of a family shows the family's total, so a family shown in two
  /// Can-Dos reads the same on both cards; an activity the course does not
  /// credit keeps its own stars.
  int starsFor(String activityId, Map<String, int> perMember) {
    if (!family.containsKey(activityId)) return perMember[activityId] ?? 0;
    return (creditedBy(perMember)[canonicalOf(activityId)] ?? 0).toInt();
  }

  /// [perMember] with each activity the course shows (and each canonical id)
  /// raised to its family's credited total (never lowered), for a display that
  /// lists activities by their own id. A family member the course does not
  /// show keeps its own stars: it is the same activity played elsewhere.
  Map<String, int> overlayOn(Map<String, int> perMember) {
    if (isEmpty) return perMember;
    final credited = creditedBy(perMember);
    final out = {...perMember};
    for (final id in {...shownIds, ...family.values}) {
      final value = (credited[canonicalOf(id)] ?? 0).toInt();
      if (value > (out[id] ?? 0)) out[id] = value;
    }
    return out;
  }
}

/// A Can-Do's credited value: the distinct canonical ids of its [shownIds]
/// and its removed activities, each counted once from [credited] (the
/// per-member values after [CourseCredit.creditedBy]).
num creditedForMission({
  required Iterable<String> shownIds,
  required String loId,
  required CourseCredit credit,
  required Map<String, num> credited,
}) {
  final ids = <String>{
    for (final id in shownIds) credit.canonicalOf(id),
    for (final id in credit.removedByLo[loId] ?? const <String>[])
      credit.canonicalOf(id),
  };
  num total = 0;
  for (final id in ids) {
    total += credited[id] ?? 0;
  }
  return total;
}

/// The whole course's credited value: every distinct canonical id the course
/// credits (shown, hidden, removed, and removed Can-Dos), once each. Without a
/// course copy, just the [shownIds].
num creditedForCourse({
  required Iterable<String> shownIds,
  required CourseCredit credit,
  required Map<String, num> credited,
}) {
  final ids = credit.isEmpty ? shownIds.toSet() : credit.family.values.toSet();
  num total = 0;
  for (final id in ids) {
    total += credited[id] ?? 0;
  }
  return total;
}
