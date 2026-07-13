import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_discovery.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/activity_map_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_signals.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

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

  /// Guards against overlapping coursemate-session discovery runs (each does
  /// networked space-hierarchy + room_preview reads).
  bool _discovering = false;

  /// Epoch ms of the last discovery run — throttles the server reads so an active
  /// sync stream doesn't re-poll the hierarchy every couple of seconds.
  int _lastDiscoveryMs = 0;

  /// Joinable facts for open sessions others started in the learner's joined
  /// courses — discovered via room_preview because they are NOT in `client.rooms`
  /// (the learner is not a member). Folded into [Client.deriveActivitySignals] as
  /// extra facts. See world-map.instructions.md ("Discovering joinable sessions").
  List<ActivitySessionFacts> _discoveredSessionFacts = const [];

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

        // A recruit ping is an `m.text` posted to the course space, so it bumps
        // the space's unread count — but the world UI has no course-space
        // timeline to open and read it, leaving the badge stuck (#7366). The map
        // is where the ping actually surfaces (the pinned pin, which *does* show
        // which activity), so the raw badge is redundant: clear it once we've
        // consumed the ping here. Course spaces carry only structural events and
        // pings (nothing else writes to them), so this never hides real content.
        // `markedUnread` (a manual mark) is left alone.
        if (space.notificationCount > 0) {
          final last = space.lastEvent;
          if (last != null) {
            await space.setReadMarker(
              last.eventId,
              mRead: last.eventId,
              public: AppSettings.sendPublicReadReceipts.value,
            );
          }
        }
      } catch (_) {
        // A space whose timeline won't load just contributes no pings.
      }
    }

    if (pinged.length == _pingedActivityIds.length &&
        pinged.containsAll(_pingedActivityIds)) {
      return;
    }
    _pingedActivityIds = pinged;
    _signals = client.deriveActivitySignals(
      pingedActivityIds: pinged,
      extraFacts: _discoveredSessionFacts,
    );
  }

  /// Discover open sessions the learner is not yet in — BOTH reads of
  /// world-map.instructions.md ("Discovering joinable sessions"):
  ///
  ///  * **coursemate sessions** — for each joined course space, enumerate its
  ///    activity-session children from the **server-side** space hierarchy;
  ///    these are not in `client.rooms`, so the hierarchy is the only way the
  ///    map sees them;
  ///  * **invited sessions** — session rooms the learner was invited to
  ///    (any course, or none): they ARE in `client.rooms`, but the invite's
  ///    stripped state carries no `pangea.activity_roles`, so seats read from
  ///    local state are phantoms (#7488) — only a preview is accurate.
  ///
  /// Each candidate is room_preview'd and emits a joinable fact while it is
  /// live, unfinished, and has a free seat. Best-effort, networked, and
  /// throttled off the sync cadence.
  Future<void> discoverCoursemateSessions(Client client) async {
    if (_discovering) return;
    final invitedSessionIds = client.invitedActivitySessionRoomIds;
    // Not synced yet — retry on the next trigger without spending the throttle.
    if (client.joinedCourseRooms.isEmpty && invitedSessionIds.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastDiscoveryMs < 8000) return;
    _discovering = true;
    _lastDiscoveryMs = nowMs;
    try {
      // Session rooms across the learner's joined courses, from the server
      // hierarchy (shared with the activity start page's join list). Rooms the
      // learner is already in flow through the client.rooms path, so drop those.
      final candidateIds = <String>{...invitedSessionIds};
      for (final id in await client.courseActivitySessionRoomIds()) {
        final existing = client.getRoomById(id);
        if (existing != null && existing.membership == Membership.join) {
          continue;
        }
        candidateIds.add(id);
      }

      if (candidateIds.isEmpty) {
        if (_discoveredSessionFacts.isNotEmpty) {
          _discoveredSessionFacts = const [];
        }
        return;
      }

      // A session is surfaced as joinable while it is live and not finished.
      // Precise open-seat filtering (the activity's total roles live on the CMS
      // plan, which the preview does not carry for v3) is a later refinement.
      final summaries = await client.loadRoomSummaries(
        candidateIds.toList(),
        l1Code: null,
      );
      // Group every previewed session by activity id so the activity start page
      // can reuse this fetch instead of round-tripping again (it applies its own
      // open-to-join filter). See DiscoveredSessionsCache.
      final byActivity = <String, Map<String, RoomSummaryResponse>>{};
      final facts = <ActivitySessionFacts>[];
      for (final entry in summaries.entries) {
        final summary = entry.value;
        final activityId = summary.activityId;
        if (activityId == null) continue; // not an activity session
        (byActivity[activityId] ??= {})[entry.key] = summary;
        // Not joinable if finished OR full (all roles taken): the same
        // `isStarted` the start page's open-to-join gate uses, so a pin the map
        // shows joinable is one the start page will actually offer a Join for,
        // never a green pin that dead-ends at "Start". `isStarted` is finished ||
        // (plan-carries-roles && no free seat); a thin-ref preview (no role plan)
        // leaves it false, so seat-unknown sessions stay permissive as before.
        if (summary.isStarted) continue;
        // "Live" means someone is actually present — filters stale rooms that
        // were never marked finished but everyone has since left.
        final presentNonBot = summary.membershipSummary.entries
            .where(
              (e) =>
                  e.value == Membership.join.name &&
                  e.key != BotName.byEnvironment,
            )
            .length;
        if (presentNonBot < 1) continue;
        facts.add(
          ActivitySessionFacts(
            activityId: activityId,
            holdsRole: false,
            collectedGoals: 0,
            totalGoals: 0,
            joinable: true,
            lastEventMs: nowMs,
          ),
        );
      }
      DiscoveredSessionsCache.instance.replaceAll(byActivity);
      _discoveredSessionFacts = facts;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        m: 'coursemate-session discovery failed',
        data: const {},
      );
    } finally {
      _discovering = false;
    }
  }

  void recomputeProgress(Client client) {
    final signals = client.deriveActivitySignals(
      pingedActivityIds: _pingedActivityIds,
      extraFacts: _discoveredSessionFacts,
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
      final uuids = client.joinedCourseRooms
          .map((r) => r.coursePlan!.uuid)
          .toList();
      await _objectiveCache.rebuildFromJoinedCourses(
        client,
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
      )).result?.toCourseLoOutline();
      // A re-scope may have raced ahead; only apply if still the active scope.
      if (_scopedCourseOutlineId != coursePlanId) return;
      _scopedCourseOutline = outline;
    } catch (_) {
      // Fail soft: the band falls back to the joined-quest resolution.
    }
    resolveProgression();
  }

  Future<void> loadCourseScopedPins(String courseId) async {
    final questResult = await QuestRepo.quest(courseId);
    final quest = questResult.result;
    if (quest == null) {
      _pins = [];
      return;
    }

    final activityCardsResult = await QuestRepo.questActivityCards(
      quest.learningObjectiveIds,
      quest.targetLanguage,
    );
    final activityCards = activityCardsResult.result;
    if (activityCards == null) {
      _pins = [];
      return;
    }

    _pins = activityCards;
  }

  Future<void> loadWorldScopedPins({
    required LatLngBounds bounds,
    String? l2,
    String? l1,
  }) async {
    _pins = await ActivityMapRepo.bboxPins(bounds: bounds, l2: l2);
  }
}
