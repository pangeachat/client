import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

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

  /// Rebuild from one outline per identity key. A key is the course's identity
  /// ([CourseLoOutline.courseId]) — the Matrix room id for a joined course; the
  /// produced outline's [courseId] IS that key. [outlineOf] resolves a key to
  /// its outline (default assumes the key is itself a quest uuid — the degenerate
  /// courseId==questId case, used by direct tests and the not-joined scoped
  /// read); the resolved outline's own [questId] is preserved so the band can
  /// dedupe courses that share a quest. [starsToUnlockOf] supplies the per-course
  /// teacher override (defaults to the standard threshold). A course that fails
  /// to resolve is skipped (rather than failing the whole set) and reported to
  /// [onError] — it must NOT be swallowed silently: a dropped course contributes
  /// no objective ids, and a fully empty cache blanks relevance banding and
  /// fail-opens the progression gate with no visible signal. [onError] is
  /// injectable so the rebuild stays unit-testable without Matrix or the network.
  Future<void> rebuild(
    List<String> courseIds, {
    Future<CourseLoOutline> Function(String courseId)? outlineOf,
    int Function(String courseId)? starsToUnlockOf,
    void Function(String courseId, Object error, StackTrace stack)? onError,
  }) async {
    final resolve = outlineOf ?? _outlineFromQuest;
    final next = <CourseLoOutline>[];
    await Future.wait(
      courseIds.map((courseId) async {
        try {
          final o = await resolve(courseId);
          next.add(
            CourseLoOutline(
              // The identity key the caller asked for (a room id for a joined
              // course), NOT the resolved outline's own id: this is what the
              // course panel scopes its rollup by, and it must stay unique per
              // course even when two courses share one quest (#8087).
              courseId: courseId,
              // ...but the quest identity travels through from the outline, so
              // the band still treats two rooms of one quest as one quest.
              questId: o.questId,
              orderedLoIds: o.orderedLoIds,
              activityIdsByLo: o.activityIdsByLo,
              starsToUnlock:
                  starsToUnlockOf?.call(courseId) ??
                  kDefaultStarsToUnlockObjective,
              earnableByActivity: o.earnableByActivity,
            ),
          );
        } catch (e, s) {
          // Skip a course that won't resolve; the rest still band and gate. But
          // report it — a silently-empty cache is exactly how banding and the
          // gate go dark unnoticed.
          onError?.call(courseId, e, s);
        }
      }),
    );
    _outlines = next;
    _ids = {for (final o in next) ...o.orderedLoIds};
  }

  /// [rebuild] from the client's joined courses — one outline per course ROOM,
  /// keyed by room id, resolving each room's quest with its teacher config
  /// (stars-to-unlock override + per-Mission activity pins). Keying by room id,
  /// not quest uuid, is the fix for #8087: one quest can back several courses,
  /// and a quest-keyed map collapses them so one course's rollup serves both.
  /// The single home for that mapping: the world map's pins manager and the
  /// course panel's star display both rebuild through here, so every surface
  /// resolves identical outlines.
  Future<void> rebuildFromJoinedCourses(
    Client client, {
    void Function(String courseId, Object error, StackTrace stack)? onError,
  }) {
    // Keyed by room id — the course's identity. Two rooms built from the same
    // quest are two distinct courses and must both survive here.
    final roomsById = <String, Room>{
      for (final room in client.joinedCourseRooms) room.id: room,
    };
    return rebuild(
      roomsById.keys.toList(),
      outlineOf: (courseId) {
        final room = roomsById[courseId]!;
        return _outlineFromQuest(
          room.coursePlan!.uuid,
          pinnedByObjective: room.teacherMode.pinnedActivitiesByObjective,
          // The course room id admits the quest owner's private activities
          // (membership-verified server-side; activities.instructions.md
          // § Ownership, visibility, and removal).
          courseRoomId: room.id,
        );
      },
      starsToUnlockOf: (courseId) =>
          roomsById[courseId]!.teacherMode.starsToUnlockObjective ??
          kDefaultStarsToUnlockObjective,
      onError: onError,
    );
  }

  static Future<CourseLoOutline> _outlineFromQuest(
    String uuid, {
    Map<String, List<String>>? pinnedByObjective,
    String? courseRoomId,
  }) async {
    final outlineResult = await QuestRepo.outline(
      uuid,
      courseRoomId: courseRoomId,
    );
    final outline = outlineResult.result;
    if (outline == null) {
      throw (outlineResult.error ?? MissingQuestException());
    }
    return outline.restrictedTo(pinnedByObjective).toCourseLoOutline();
  }
}
