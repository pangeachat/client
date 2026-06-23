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
  /// standard threshold). A course that fails to resolve is skipped (rather than
  /// failing the whole set) and reported to [onError] — it must NOT be swallowed
  /// silently: a dropped course contributes no objective ids, and a fully empty
  /// cache blanks relevance banding and fail-opens the progression gate with no
  /// visible signal. [onError] is injectable so the rebuild stays unit-testable
  /// without Matrix, the network, or Sentry.
  Future<void> rebuild(
    List<String> courseUuids, {
    Future<CourseLoOutline> Function(String uuid)? outlineOf,
    int Function(String uuid)? starsToUnlockOf,
    void Function(String uuid, Object error, StackTrace stack)? onError,
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
        } catch (e, s) {
          // Skip a course that won't resolve; the rest still band and gate. But
          // report it — a silently-empty cache is exactly how banding and the
          // gate go dark unnoticed.
          onError?.call(uuid, e, s);
        }
      }),
    );
    _outlines = next;
    _ids = {for (final o in next) ...o.orderedLoIds};
  }

  static Future<CourseLoOutline> _outlineFromQuest(String uuid) async =>
      (await QuestRepo.outline(uuid)).toCourseLoOutline();
}
