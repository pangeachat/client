import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/chat/chat_details/teacher_mode_model.dart';
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

  /// Rebuild from the joined courses' quest outlines. [outlineOf] resolves a
  /// course key to its outline (defaults to the v3 quest read layer, which
  /// treats the key as a quest uuid; [rebuildFromJoinedCourses] keys by course
  /// room id instead — see #8087); [starsToUnlockOf] supplies the per-course
  /// teacher override (defaults to the standard threshold). A course that fails
  /// to resolve is skipped (rather than failing the whole set) and reported to
  /// [onError] — it must NOT be swallowed silently: a dropped course
  /// contributes no objective ids, and a fully empty cache blanks relevance
  /// banding and fail-opens the progression gate with no visible signal.
  /// [onError] is injectable so the rebuild stays unit-testable without
  /// Matrix, the network, or Sentry.
  Future<void> rebuild(
    List<String> courseKeys, {
    Future<CourseLoOutline> Function(String key)? outlineOf,
    int Function(String key)? starsToUnlockOf,
    void Function(String key, Object error, StackTrace stack)? onError,
  }) async {
    final resolve = outlineOf ?? _outlineFromQuest;
    final next = <CourseLoOutline>[];
    await Future.wait(
      courseKeys.map((key) async {
        try {
          final o = await resolve(key);
          next.add(
            CourseLoOutline(
              // The key the caller asked for, not the resolved outline's own
              // id: this is the key the course panel scopes its rollup by.
              courseId: key,
              // The resolved outline's quest identity survives the re-key so
              // the world-map band can dedupe a quest joined in two rooms.
              questId: o.questId,
              orderedLoIds: o.orderedLoIds,
              activityIdsByLo: o.activityIdsByLo,
              starsToUnlock:
                  starsToUnlockOf?.call(key) ?? kDefaultStarsToUnlockObjective,
              earnableByActivity: o.earnableByActivity,
            ),
          );
        } catch (e, s) {
          // Skip a course that won't resolve; the rest still band and gate. But
          // report it — a silently-empty cache is exactly how banding and the
          // gate go dark unnoticed.
          onError?.call(key, e, s);
        }
      }),
    );
    _outlines = next;
    _ids = {for (final o in next) ...o.orderedLoIds};
  }

  /// [rebuild] from the client's joined courses — each course room with its
  /// quest uuid and teacher config (stars-to-unlock override + per-Mission
  /// activity pins). The single home for that mapping: the world map's pins
  /// manager and the course panel's star display both rebuild through here, so
  /// every surface resolves identical outlines. Pins are applied as a pure copy
  /// per course (never to the shared quest-outline cache), so two courses
  /// sharing a quest can restrict differently.
  ///
  /// Keyed by course ROOM id, not quest uuid: one quest launched into two
  /// rooms is two courses, and uuid keys collapsed them to a single entry
  /// (last room won), crossing their star totals (#8087).
  Future<void> rebuildFromJoinedCourses(
    Client client, {
    void Function(
      String roomId,
      String questId,
      Object error,
      StackTrace stack,
    )?
    onError,
  }) {
    final questIdByRoom = <String, String>{
      for (final room in client.joinedCourseRooms)
        room.id: room.coursePlan!.uuid,
    };
    final modes = <String, TeacherModeModel>{
      for (final room in client.joinedCourseRooms) room.id: room.teacherMode,
    };
    return rebuild(
      questIdByRoom.keys.toList(),
      // A joined member's outline read carries the course room id, so the
      // quest owner's private activities are included (membership-verified
      // server-side; activities.instructions.md § Ownership, visibility, and
      // removal).
      outlineOf: (roomId) => _outlineFromQuest(
        questIdByRoom[roomId]!,
        pinnedByObjective: modes[roomId]?.pinnedActivitiesByObjective,
        courseRoomId: roomId,
      ),
      starsToUnlockOf: (roomId) =>
          modes[roomId]?.starsToUnlockObjective ??
          kDefaultStarsToUnlockObjective,
      onError: onError == null
          ? null
          : (roomId, e, s) => onError(roomId, questIdByRoom[roomId]!, e, s),
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
