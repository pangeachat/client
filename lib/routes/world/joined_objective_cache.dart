import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';

/// Holds the learner's joined-course quest outlines: each course's ordered
/// learning-objective sequence and the activities that satisfy each objective.
/// World-map relevance banding reads the flattened [ids] (joined-course vs merely
/// level-appropriate, without a per-pin lookup), and the progression gate reads
/// the ordered [outlines] (see the Priority matrix in world-map.instructions.md
/// and the gate in quests.instructions.md).
///
/// Rebuilt wholesale on course join/leave — the simplest invalidation, and the
/// set is small. Resolution is injectable so the rebuild is unit-testable
/// without Matrix or the network.
class JoinedObjectiveCache {
  List<CourseLoOutline> _outlines = const [];
  Set<String> _ids = const {};

  /// The ordered per-course outlines that feed the progression gate. Empty until
  /// the first [rebuild] completes.
  List<CourseLoOutline> get outlines => _outlines;

  /// The flattened, deduped objective-id set across all joined courses, for
  /// relevance banding.
  Set<String> get ids => _ids;

  /// Rebuild from the joined courses' quest outlines. [outlineOf] resolves a
  /// course-plan uuid to its outline (defaults to the v3 quest read layer);
  /// [starsToUnlockOf] supplies the per-course teacher override (defaults to the
  /// standard threshold). A course that fails to resolve is skipped rather than
  /// failing the whole set, so one bad course can't blank the banding or gate.
  Future<void> rebuild(
    List<String> courseUuids, {
    Future<CourseLoOutline> Function(String uuid)? outlineOf,
    int Function(String uuid)? starsToUnlockOf,
  }) async {
    final resolve = outlineOf ?? _outlineFromQuest;
    final next = <CourseLoOutline>[];
    await Future.wait(
      courseUuids.map((uuid) async {
        try {
          final o = await resolve(uuid);
          next.add(
            CourseLoOutline(
              orderedLoIds: o.orderedLoIds,
              activityIdsByLo: o.activityIdsByLo,
              starsToUnlock:
                  starsToUnlockOf?.call(uuid) ?? kDefaultStarsToUnlockObjective,
            ),
          );
        } catch (_) {
          // Skip a course that won't resolve; the rest still band and gate.
        }
      }),
    );
    _outlines = next;
    _ids = {for (final o in next) ...o.orderedLoIds};
  }

  static Future<CourseLoOutline> _outlineFromQuest(String uuid) async {
    final outline = await QuestRepo.outline(uuid);
    return CourseLoOutline(
      orderedLoIds: outline.quest.learningObjectiveIds,
      activityIdsByLo: {
        for (final group in outline.groups)
          group.objective.id: group.activities.map((a) => a.activityId).toSet(),
      },
    );
  }
}
