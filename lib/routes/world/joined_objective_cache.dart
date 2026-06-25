import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';

/// Holds the learner's joined-course quest outlines: each course's ordered
/// learning-objective sequence and the activities that satisfy each objective.
/// World-map relevance banding resolves these ordered [outlines] (plus the
/// learner's per-activity stars) into a [ProgressionResolution] via [resolution]
/// — the shared next-Mission gradient the Priority matrix ranks toward (see
/// world-map.instructions.md and quests.instructions.md). [ids] is the flattened
/// objective-id set, used only to detect a cache that resolved nothing.
///
/// Rebuilt wholesale on course join/leave — the simplest invalidation, and the
/// set is small. Resolution is injectable so the rebuild is unit-testable
/// without Matrix or the network.
class JoinedObjectiveCache {
  List<CourseLoOutline> _outlines = const [];
  Set<String> _ids = const {};

  /// The ordered per-course outlines that feed the progression resolver. Empty
  /// until the first [rebuild] completes.
  List<CourseLoOutline> get outlines => _outlines;

  /// The flattened, deduped objective-id set across all joined courses. Used to
  /// detect a cache that resolved nothing (so the rebuild can self-heal).
  Set<String> get ids => _ids;

  /// Resolve the shared [ProgressionResolution] for the world map's relevance
  /// band from the cached [outlines] and the learner's [starsByActivity]
  /// (per-activity star totals from session room state, supplied by the
  /// controller). [extraOutlines] adds in-scope outlines the learner hasn't
  /// joined — e.g. a course-scoped map ranks toward the viewed course's next
  /// Mission even before it's joined. Pure and cheap; the controller calls it
  /// where the inputs change (course join/leave, star award), not per frame.
  ProgressionResolution resolution(
    Map<String, int> starsByActivity, {
    Iterable<CourseLoOutline> extraOutlines = const [],
  }) => resolveProgression(
    outlines: [..._outlines, ...extraOutlines],
    starsByActivity: starsByActivity,
  );

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
