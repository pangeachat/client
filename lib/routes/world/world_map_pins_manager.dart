import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/activity_map_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';

class WorldMapPinsManager {
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static void set(bool open) {
    if (notifier.value != open) notifier.value = open;
  }

  /// The activity pins currently shown — the active context's set (the whole
  /// world, or a selected quest's activities). Thin: id, title, point.
  List<QuestActivityCard> _pins = [];

  Map<String, PinSignals> _signals = {};
  Map<String, int> _userStars = {};
  Map<String, MapCompletionFilter> _completion = {};

  /// The shared next-Mission resolution the relevance band ranks toward, resolved
  /// from the objective cache's outlines + [_userStars]. Recomputed where its
  /// inputs change — the objective cache rebuilds (course join/leave) and user
  /// stars change on room sync — NOT per frame. See world-map.instructions.md.
  ProgressionResolution _progression = ProgressionResolution.empty;

  /// Learning-objective ids across the learner's joined courses, for relevance
  /// banding. Rebuilt async on course join/leave (see [_maybeRebuildObjectiveCache]).
  final JoinedObjectiveCache _objectiveCache = JoinedObjectiveCache();

  /// The joined-course uuids [_objectiveCache] was last (re)built from. The
  /// initial build happens on client-set, but the joined-course rooms (or their
  /// outlines) may not be ready yet; tracking the set lets the sync listener
  /// rebuild when it changes — or when a prior build resolved nothing — instead
  /// of the banding + gate staying blank for the whole session.
  Set<String> _objectiveCacheUuids = const {};

  /// Guards against overlapping objective-cache rebuilds (and stops a
  /// persistently-failing course from rebuilding on every single sync).
  bool _objectiveCacheRebuilding = false;

  /// The course-plan id [_scopedCourseOutline] was resolved for, so a re-scope to
  /// the same course doesn't re-fetch and a re-scope away clears it.
  String? _scopedCourseOutlineId;

  /// The viewed course's outline when the map is scoped to a course the learner
  /// has NOT joined: a course-scoped map ranks toward that course's next Mission
  /// even before joining (Will's decision). Null on the world view or when the
  /// scoped course is already a joined course (its outline is in the cache).
  CourseLoOutline? _scopedCourseOutline;

  /// Activity ids with a recently-pinged open session (best-effort, scanned from
  /// joined course-space messages). Folded into [_signals].
  Set<String> _pingedActivityIds = {};

  Map<String, PinSignals> get signals => _signals;

  ProgressionResolution get progression => _progression;

  /// Resolve a [MapFocus] to a map coordinate, or null if not resolvable yet.
  /// Exhaustive over the sealed [MapFocus]: adding a focus kind makes this a
  /// compile error until its arm is added — that is the extension seam.
  LatLng? focusPoint(MapFocus? focus) {
    switch (focus) {
      case null:
        return null;
      case ActivityFocus(:final activityId):
        for (final card in _pins) {
          if (card.activityId == activityId) return card.point;
        }
        return null;
    }
  }

  List<LatLng> get focusPoints =>
      _pins.map((c) => c.point).whereType<LatLng>().toList();

  List<QuestActivityCard> filteredPins(
    bool Function(QuestActivityCard) filter,
  ) => _pins.where(filter).toList();

  MapCompletionFilter? activityCompletionStatus(String activityId) =>
      _completion[activityId];

  int? activityStarsEarned(String activityId) => _userStars[activityId];

  /// Activity ids the learner has earned at least one star in — the trail the
  /// ranking reserves slots for (world-map.instructions.md, "Goal Progress").
  Set<String> get progressedActivityIds => {
    for (final e in _userStars.entries)
      if (e.value > 0) e.key,
  };

  void resetScopedCourseOutline() {
    if (_scopedCourseOutline != null || _scopedCourseOutlineId != null) {
      _scopedCourseOutline = null;
      _scopedCourseOutlineId = null;
      resolveProgression();
    }
  }

  /// Best-effort pinged detection: scan joined course spaces' recent messages
  /// for the host's recruit ping (carries `pangea.activity.id`), within a day.
  /// A ping leaves no persistent room state, so this proxy is intentionally
  /// approximate — its efficacy is worth watching (world-map.instructions.md).
  Future<void> recomputePinged(Client client) async {
    final pinged = <String>{};
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final spaces = client.rooms.where(
      (r) =>
          r.isSpace && r.membership == Membership.join && r.coursePlan != null,
    );

    for (final space in spaces) {
      try {
        final timeline = await space.getTimeline();
        for (final e in timeline.events) {
          if (!e.originServerTs.isAfter(cutoff)) continue;
          final id = e.content['pangea.activity.id'];
          if (id is String && id.isNotEmpty) pinged.add(id);
        }
        timeline.cancelSubscriptions();
      } catch (_) {
        // A space whose timeline won't load just contributes no pings.
      }
    }

    if (pinged.length == _pingedActivityIds.length &&
        pinged.containsAll(_pingedActivityIds)) {
      return;
    }
    _pingedActivityIds = pinged;
    _signals = client.deriveActivitySignals(pingedActivityIds: pinged);
  }

  void recomputeProgress(Client client) {
    final signals = client.deriveActivitySignals(
      pingedActivityIds: _pingedActivityIds,
    );
    final userStars = client.userStarsByActivity;
    final completion = client.activityCompletionStatuses;

    _signals = signals;
    _userStars = userStars;
    _completion = completion;
    resolveProgression();
  }

  /// Re-resolve the cached [_progression] from the objective cache's outlines (+
  /// any course-scoped outline) and the learner's current per-activity stars.
  /// Called where the inputs change — stars on room sync, the objective cache on
  /// course join/leave, and a course re-scope — never per frame.
  void resolveProgression() {
    _progression = _objectiveCache.resolution(
      _userStars,
      extraOutlines: _scopedCourseOutline == null
          ? const []
          : [_scopedCourseOutline!],
    );
  }

  /// Rebuild the joined-course outlines (a few quest reads), reading each
  /// course's teacher override for the stars-to-unlock threshold, then re-rank.
  /// Guarded so overlapping syncs don't stack rebuilds. A course whose outline
  /// fails to resolve is logged (not silently dropped): an empty cache means no
  /// relevance banding and a fail-open gate, which is otherwise invisible.
  Future<void> rebuildObjectiveCache(Client client) async {
    if (_objectiveCacheRebuilding) return;
    _objectiveCacheRebuilding = true;
    try {
      final courseRooms = client.joinedCourseRooms;
      final uuids = courseRooms.map((r) => r.coursePlan!.uuid).toList();
      final thresholds = <String, int>{
        for (final r in courseRooms)
          r.coursePlan!.uuid:
              r.teacherMode.starsToUnlockObjective ??
              kDefaultStarsToUnlockObjective,
      };
      await _objectiveCache.rebuild(
        uuids,
        starsToUnlockOf: (uuid) =>
            thresholds[uuid] ?? kDefaultStarsToUnlockObjective,
        onError: (uuid, e, s) => ErrorHandler.logError(
          e: e,
          s: s,
          m: 'JoinedObjectiveCache: course outline failed to resolve',
          data: {'courseUuid': uuid},
        ),
      );
      _objectiveCacheUuids = uuids.toSet();
      resolveProgression(); // re-resolve the band with the loaded outlines
    } finally {
      _objectiveCacheRebuilding = false;
    }
  }

  /// Rebuild the objective cache when the joined-course set has changed since the
  /// last build, or when it resolved nothing while courses exist (the rooms or
  /// their outlines weren't ready at the initial build, or a read transiently
  /// failed). Idempotent for an unchanged, already-populated set, so it's safe on
  /// every sync; the in-flight guard keeps a persistently-failing course from
  /// rebuilding more than once at a time, and it self-heals once the data is fixed.
  bool shouldRebuildObjectiveCache(Client client) {
    if (_objectiveCacheRebuilding) return false;
    final uuids = client.joinedCourseRooms
        .map((r) => r.coursePlan!.uuid)
        .toSet();

    final setChanged =
        uuids.length != _objectiveCacheUuids.length ||
        !uuids.containsAll(_objectiveCacheUuids);

    final emptyButHasCourses = _objectiveCache.ids.isEmpty && uuids.isNotEmpty;
    return setChanged || emptyButHasCourses;
  }

  /// Resolve the viewed course's outline for a course-scoped map so the band
  /// ranks toward that course's next Mission even before the learner joins it
  /// (Will's decision). Skipped when the course is already a joined course (its
  /// outline is in the objective cache) or already resolved for this scope.
  Future<void> ensureScopedCourseOutline(String coursePlanId) async {
    if (_scopedCourseOutlineId == coursePlanId) return;
    _scopedCourseOutlineId = coursePlanId;
    _scopedCourseOutline = null;
    if (_objectiveCacheUuids.contains(coursePlanId)) {
      resolveProgression(); // joined: the cache already carries it
      return;
    }
    try {
      final outline = (await QuestRepo.outline(
        coursePlanId,
      )).toCourseLoOutline();
      // A re-scope may have raced ahead; only apply if still the active scope.
      if (_scopedCourseOutlineId != coursePlanId) return;
      _scopedCourseOutline = outline;
    } catch (_) {
      // Fail soft: the band falls back to the joined-quest resolution.
    }
    resolveProgression();
  }

  Future<void> loadCourseScopedPins(String courseId) async {
    _pins = await QuestRepo.questPins(courseId);
  }

  Future<void> loadWorldScopedPins({
    required LatLngBounds bounds,
    String? l2,
    String? l1,
  }) async {
    _pins = await ActivityMapRepo.bboxPins(bounds: bounds, l2: l2, l1: l1);
  }
}
