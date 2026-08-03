import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
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
import 'package:fluffychat/features/room_summaries/activity_session_previews_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_signals.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

/// The pure rule behind [WorldMapPinsManager.loadSessionParticipants]'s room
/// selection (#8045).
///
/// A room never filled ([everFilled] false) earns a refill while its seats are
/// still resting on unloaded membership ([hasUnresolvedSeats]) — the startup
/// case, where no `m.room.member` event has been read back into room state at
/// all. A room already filled earns one only when its joined-member count has
/// *moved* ([filledAtJoinedCount] vs [joinedCount]): sync merges the room
/// summary even for the partial rooms whose member events it skips, so a moved
/// count is real evidence that someone joined or left since. Comparing against
/// the count at fill time — rather than asking whether the loaded list looks
/// complete — is what keeps this loop-free: a room whose count the server
/// reports inconsistently re-qualifies once and then never again.
@visibleForTesting
bool needsParticipantRefill({
  required bool everFilled,
  required int? filledAtJoinedCount,
  required int? joinedCount,
  required bool hasUnresolvedSeats,
}) => everFilled ? filledAtJoinedCount != joinedCount : hasUnresolvedSeats;

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

  // Star-tier inputs, precomputed once per sync (each a single rooms pass) so
  // resolving a pin's display state / star level is an O(roles) lookup rather
  // than an O(rooms) rescan per pin (world-map.instructions.md, "Goal Progress").
  Map<String, List<OwnRoleAwards>> _ownRoleAwards = {};
  Map<String, Set<String>> _completedRoles = {};
  Map<String, Set<String>> _allRoles = {};

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

  /// Epoch ms of the last discovery run — throttles the server reads so the two
  /// triggers (sync ticks and camera settles while panning) don't re-poll the
  /// hierarchy on every event. 3s keeps the matrix's live facts feeling current
  /// while scrolling without multiplying the preview reads.
  int _lastDiscoveryMs = 0;

  /// Joinable facts for open sessions others started in the learner's joined
  /// courses — discovered via room_preview because they are NOT in `client.rooms`
  /// (the learner is not a member). Folded into [Client.deriveActivitySignals] as
  /// extra facts. See world-map.instructions.md ("Discovering joinable sessions").
  List<ActivitySessionFacts> _discoveredSessionFacts = const [];

  /// Room id → the joined-member count its member list was last filled at, so
  /// [loadSessionParticipants] sweeps a room once rather than on every sync
  /// tick. A *changed* count re-qualifies it: sync merges the room summary even
  /// for the partial rooms whose member events it skips, so a count that no
  /// longer matches means someone joined or left since the fill. An unchanged
  /// count never re-triggers, so a room the server reports inconsistently can't
  /// put the sweep in a loop.
  final Map<String, int?> _participantsLoadedAtCount = {};

  /// Guards against overlapping member-refill sweeps.
  bool _loadingParticipants = false;

  /// Epoch ms of the last member-refill sweep. A filled room is skipped by
  /// [_participantsLoadedAtCount], so this only paces retries of rooms the
  /// sweep failed to fill and the drain of a long backlog.
  int _lastParticipantLoadMs = 0;

  /// Rooms filled per sweep. Most fills resolve from the local database with no
  /// network at all, but a learner with a long activity history shouldn't do
  /// them all at once; the sync listener drains the remainder.
  static const int _participantLoadBatch = 25;

  /// Course members available to fill activity roles in the currently
  /// course-scoped map (the start page's invite math via
  /// [CoursePlanRoomExtension.availableActivityParticipants]), or null on the
  /// world map / an unjoined course. Drives dimming of `available` pins whose
  /// role count exceeds it; course-only, so cleared when leaving course scope.
  int? _courseAvailableParticipants;

  Map<String, PinSignals> get signals => _signals;

  int? get courseAvailableParticipants => _courseAvailableParticipants;

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

  /// The learner's star tier for [card], resolved hydration-free against the
  /// card's current thin goals, falling back to the room-derived path for cards
  /// without thin goals (world-map.instructions.md, "Goal Progress"). Reuses the
  /// precomputed star-input maps so it never rescans rooms.
  ActivityStarLevel starLevelOf(QuestActivityCard card) {
    final id = card.activityId;
    return starLevelForCard(card, _ownRoleAwards[id] ?? const []) ??
        starLevelFor(
          _completedRoles[id] ?? const {},
          _allRoles[id] ?? card.roleIds,
        );
  }

  /// The activity's resolved display [ActivityPinState]: a live-session state
  /// (from [_signals]) wins the colour, else the completed star tier layers in
  /// `inProgress`, else the plain `available` default. The single source shared
  /// by the Status filter ([WorldMapFilterState.include]) and the pin renderer
  /// so the two can never drift (world-map.instructions.md, "Pin state").
  ActivityPinState displayStateOf(QuestActivityCard card) {
    final live = _signals[card.activityId]?.state;
    if (live != null) return live;
    return starLevelOf(card) == ActivityStarLevel.none
        ? ActivityPinState.available
        : ActivityPinState.inProgress;
  }

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

  /// Refresh [courseAvailableParticipants] from the scoped joined [courseRoom]
  /// (the count that dims `available` pins the learner can't yet start).
  Future<void> loadCourseAvailableParticipants(Room courseRoom) async {
    _courseAvailableParticipants = await courseRoom
        .availableActivityParticipants();
  }

  /// Clear the participant count (world map, or an unjoined course) so no pins dim.
  void clearCourseAvailableParticipants() {
    _courseAvailableParticipants = null;
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
    _signals = client.deriveActivitySignals(
      pingedActivityIds: pinged,
      extraFacts: _discoveredSessionFacts,
    );
  }

  /// Whether [room] earns a member refill this sweep — the Matrix-reading shell
  /// over [needsParticipantRefill].
  bool _needsParticipantRefill(Room room) => needsParticipantRefill(
    everFilled: _participantsLoadedAtCount.containsKey(room.id),
    filledAtJoinedCount: _participantsLoadedAtCount[room.id],
    joinedCount: room.summary.mJoinedMemberCount,
    hasUnresolvedSeats: room.hasUnresolvedSeats,
  );

  /// Refill the member lists behind the map's seat math and participant rows.
  ///
  /// `m.room.member` events never ride the SDK's preloaded-state path (they
  /// live in their own store and return to room state only through
  /// [Room.requestParticipants]), so at startup `Room.getParticipants()` is
  /// empty for every session room the learner hasn't opened this session. That
  /// left large cards rendering on guesses (#8045): the avatar row read empty,
  /// and [Room.assignedRoles] scored every seat on the "unknown membership =
  /// still occupied" fallback ([roleHolderVacated]) rather than on evidence —
  /// so the pending/active split and the seat row were both decided without the
  /// facts they are supposed to read.
  ///
  /// Cheap by construction: [Room.requestParticipants] refills from the local
  /// database first and reaches the network only when that is still short of
  /// the room's summary counts, and a room is swept once until its member count
  /// moves ([_needsParticipantRefill]). Returns true when it filled anything,
  /// so the caller re-derives signals.
  Future<bool> loadSessionParticipants(Client client) async {
    if (_loadingParticipants) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastParticipantLoadMs < 3000) return false;

    final pending = client.rooms
        .where(
          (r) =>
              r.membership == Membership.join &&
              r.activityId != null &&
              // A finished session produces no live pin state and renders no
              // participant row, so its seats never reach the screen.
              !r.hasCompletedRole &&
              _needsParticipantRefill(r),
        )
        .take(_participantLoadBatch)
        .toList();
    if (pending.isEmpty) return false;

    _loadingParticipants = true;
    _lastParticipantLoadMs = nowMs;
    var filled = false;
    try {
      for (final room in pending) {
        try {
          // `cache: true` is load-bearing: it defaults to `encrypted`, and
          // without it the SDK returns the members without writing them into
          // room state — leaving `getParticipants()`, which the seat math and
          // the avatar row actually read, exactly as empty as before.
          await room.requestParticipants(
            const [Membership.join, Membership.invite, Membership.knock],
            false,
            true,
          );
          _participantsLoadedAtCount[room.id] = room.summary.mJoinedMemberCount;
          filled = true;
        } catch (e, s) {
          // A room that won't load its members keeps the fallback seats it
          // already had; the throttle above paces the retry.
          ErrorHandler.logError(
            e: e,
            s: s,
            m: 'session participant refill failed',
            data: {'roomId': room.id},
          );
        }
      }
    } finally {
      _loadingParticipants = false;
    }
    return filled;
  }

  /// Discover open sessions the learner is not yet in — BOTH reads of
  /// world-map.instructions.md ("Discovering joinable sessions"):
  ///
  ///  * **coursemate sessions** — one batched read of the joined course spaces
  ///    against the space-scoped activity_session_previews module, which
  ///    returns previews for only their activity-session children, complete
  ///    regardless of how many rooms a course holds (#7982); these rooms are
  ///    not in `client.rooms`, so the server is the only way the map sees them;
  ///  * **invited sessions** — session rooms the learner was invited to
  ///    (any course, or none): they ARE in `client.rooms`, but the invite's
  ///    stripped state carries no `pangea.activity_roles`, so seats read from
  ///    local state are phantoms (#7488) — only a preview is accurate. The
  ///    space-scoped module can't see them, so they keep the per-room
  ///    room_preview read.
  ///
  /// A previewed candidate emits a joinable fact while it is live, unfinished,
  /// and has a free seat. Best-effort, networked, and throttled — triggered off
  /// sync ticks AND camera settles (panning to a new viewport should rank
  /// against current live facts, not wait for a sync).
  Future<void> discoverCoursemateSessions(Client client) async {
    if (_discovering) return;
    final invitedSessionIds = client.invitedActivitySessionRoomIds;
    // Not synced yet — retry on the next trigger without spending the throttle.
    if (client.joinedCourseRooms.isEmpty && invitedSessionIds.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastDiscoveryMs < 3000) return;
    _discovering = true;
    _lastDiscoveryMs = nowMs;
    try {
      final courseSpaceIds = client.joinedCourseRooms.map((r) => r.id).toList();
      // The two reads fail independently — a module error must not cost this
      // cycle's invited previews (nor vice versa). A FAILED course read leaves
      // [courseSessions] null so the clear branch below is skipped: only a
      // successful read that finds nothing may drop last-known facts.
      Map<String, RoomSummaryResponse>? courseSessions;
      Map<String, RoomSummaryResponse> invitedPreviews = const {};
      await Future.wait([
        () async {
          if (courseSpaceIds.isEmpty) {
            courseSessions = const {};
            return;
          }
          try {
            courseSessions = await client.loadActivitySessionPreviews(
              courseSpaceIds,
              l1Code: null,
            );
          } catch (e, s) {
            ErrorHandler.logError(
              e: e,
              s: s,
              m: 'activity_session_previews read failed',
              data: const {},
            );
          }
        }(),
        () async {
          if (invitedSessionIds.isEmpty) return;
          try {
            invitedPreviews = await client.loadRoomSummaries(
              invitedSessionIds.toList(),
              l1Code: null,
            );
          } catch (e, s) {
            ErrorHandler.logError(
              e: e,
              s: s,
              m: 'invited-session preview read failed',
              data: const {},
            );
          }
        }(),
      ]);
      // Rooms the learner is already in flow through the client.rooms path, so
      // drop those from the module's course-wide result.
      final summaries = <String, RoomSummaryResponse>{
        for (final entry in (courseSessions ?? const {}).entries)
          if (client.getRoomById(entry.key)?.membership != Membership.join)
            entry.key: entry.value,
        ...invitedPreviews,
      };

      if (summaries.isEmpty) {
        if (courseSessions == null) return; // failed read — keep stale facts
        if (_discoveredSessionFacts.isNotEmpty) {
          _discoveredSessionFacts = const [];
        }
        // No session rooms left in any joined course → drop stale previews so a
        // card whose open session vanished stops reading it as Open.
        DiscoveredSessionsCache.instance.clear();
        return;
      }

      // A session is surfaced as joinable while it is live and not finished.
      // Precise open-seat filtering (the activity's total roles live on the CMS
      // plan, which the preview does not carry for v3) is a later refinement.
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

    _signals = signals;
    _userStars = userStars;
    _ownRoleAwards = client.ownRoleAwardsByActivity;
    _completedRoles = client.completedRolesByActivity;
    _allRoles = client.roleIdsByActivity;
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

  Future<void> loadCourseScopedPins(
    String courseId, {
    Map<String, List<String>>? pinnedActivitiesByObjective,
    String? courseRoomId,
  }) async {
    // One choreo read: the quest's activities at its own L2, LO-grouped
    // server-side. [courseRoomId] admits the quest owner's private activities
    // when this learner is a joined member of the course.
    final activityCardsResult = await QuestRepo.questActivityCards(
      courseId,
      courseRoomId: courseRoomId,
    );
    final activityCards = activityCardsResult.result;
    if (activityCards == null) {
      _pins = [];
      return;
    }

    _pins = _restrictCards(activityCards, pinnedActivitiesByObjective);
  }

  /// Course-scoped marker filter for per-course activity pinning (org quests
  /// doc, client#7748): a card stays when at least one of its Mission refs
  /// allows it — the same fail-open rule as the outline restriction, via the
  /// shared [effectivePinnedActivityIds]. Null pins (not joined / unset) show
  /// everything; the WORLD-scoped map is deliberately never filtered.
  static List<QuestActivityCard> _restrictCards(
    List<QuestActivityCard> cards,
    Map<String, List<String>>? pinnedByObjective,
  ) {
    if (pinnedByObjective == null || pinnedByObjective.isEmpty) return cards;
    final availableByLo = <String, Set<String>>{};
    for (final card in cards) {
      for (final loId in card.learningObjectiveRefs) {
        (availableByLo[loId] ??= <String>{}).add(card.activityId);
      }
    }
    final allowedByLo = {
      for (final entry in availableByLo.entries)
        entry.key: effectivePinnedActivityIds(
          entry.value,
          pinnedByObjective[entry.key],
        ),
    };
    return cards
        .where(
          (card) => card.learningObjectiveRefs.any(
            (loId) => allowedByLo[loId]?.contains(card.activityId) ?? true,
          ),
        )
        .toList();
  }

  Future<void> loadWorldScopedPins({
    required LatLngBounds bounds,
    String? l2,
    String? l1,
  }) async {
    _pins = await ActivityMapRepo.bboxPins(bounds: bounds, l2: l2);
  }
}
