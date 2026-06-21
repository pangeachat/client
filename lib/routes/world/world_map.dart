import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/activity_map_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The colour a pin reads as for its [ActivityPinState] (see
/// world-map.instructions.md): locked gray, unlocked purple, joinable green.
/// Completion is not a colour — it renders as the inner gold fill in [_stateDot].
Color _stateColor(ActivityPinState state) {
  switch (state) {
    case ActivityPinState.joinable:
      return const Color(0xFF34A853); // green — an open session to join
    case ActivityPinState.unlocked:
      return const Color(0xFF7B61FF); // purple — available, not started
    case ActivityPinState.locked:
      return Colors.grey;
  }
}

/// The state-coloured pin body with the progress fill: an outer [state]-coloured
/// disc, an inner gold disc whose radius scales with [fill] (0..1 — stars earned
/// toward the activity's total), and an optional [glyph] on top. The fill is
/// linear in radius (`r = innerRadius·fill`), so a full activity reads as a solid
/// gold centre while a fresh one shows none. Design: world-map.instructions.md.
Widget _stateDot({
  required ActivityPinState state,
  required double diameter,
  required double borderWidth,
  double fill = 0,
  Widget? glyph,
}) {
  final inner = (diameter - 2 * borderWidth) * fill.clamp(0.0, 1.0);
  return Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(
      color: _stateColor(state),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: borderWidth),
      boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (inner > 0)
          Container(
            width: inner,
            height: inner,
            decoration: const BoxDecoration(
              color: AppConfig.gold,
              shape: BoxShape.circle,
            ),
          ),
        ?glyph,
      ],
    ),
  );
}

/// Derive each activity's live [PinSignals] from the user's Matrix rooms: the
/// highest-wins colour state on the `locked < unlocked < joinable` ladder, a
/// 0..1 completion fraction (stars earned toward the activity's total), recency
/// for the newest open session, and the pinged flag. Also returns the learner's
/// star total per activity (max across their sessions of it) for the
/// progression gate.
///
/// State derives from sessions the client can see locally: the user's own
/// sessions give unlocked, and any visible session with a free role the user
/// isn't bound to gives joinable. Open sessions by strangers are not in
/// `client.rooms`, so map-wide open-session discovery needs a backend endpoint
/// (see world-map.instructions.md). `locked` is layered on at render time from
/// the progression gate (quests.instructions.md): it depends on the pin's
/// objective refs, which aren't in room state, so it can't be resolved here.
({Map<String, PinSignals> signals, Map<String, int> stars})
_deriveActivitySignals(
  Client client, {
  required Set<String> pingedActivityIds,
}) {
  final stateById = <String, ActivityPinState>{};
  final newestOpenMs = <String, int>{};
  final fractionById = <String, double>{};
  final starsById = <String, int>{};
  for (final room in client.rooms) {
    final activityId = room.activityId;
    if (activityId == null) continue;
    // The learner's own progress in this session (a role they hold): stars =
    // collected goals; fraction = collected / the role's total goals. Keep the
    // best across multiple sessions of the same activity.
    final role = room.ownRole;
    if (role != null) {
      final collected = room.ownCompletedGoals.length;
      if (collected > (starsById[activityId] ?? 0)) {
        starsById[activityId] = collected;
      }
      final total = role.allGoals.length;
      final frac = total > 0 ? (collected / total).clamp(0.0, 1.0) : 0.0;
      if (frac > (fractionById[activityId] ?? 0)) {
        fractionById[activityId] = frac;
      }
    }
    // Colour state: a free role the user hasn't taken → joinable; else holding a
    // role → unlocked (completion shows as the fill, not a separate state).
    ActivityPinState? state;
    if (room.numRemainingRoles > 0 && room.ownRoleState == null) {
      state = ActivityPinState.joinable;
      final ms = room.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      if (ms > (newestOpenMs[activityId] ?? 0)) newestOpenMs[activityId] = ms;
    } else if (role != null) {
      state = ActivityPinState.unlocked;
    }
    if (state == null) continue;
    final existing = stateById[activityId];
    if (existing == null || state.index > existing.index) {
      stateById[activityId] = state; // ladder order = enum index order
    }
  }

  const windowMs = 24 * 60 * 60 * 1000; // recency decays to 0 over a day
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final signals = <String, PinSignals>{};
  stateById.forEach((id, state) {
    final ms = newestOpenMs[id];
    final age = ms == null ? windowMs : nowMs - ms;
    final recency = (1.0 - age / windowMs).clamp(0.0, 1.0);
    signals[id] = PinSignals(
      state: state,
      completionFraction: fractionById[id] ?? 0,
      pinged: pingedActivityIds.contains(id),
      recency: recency,
    );
  });
  return (signals: signals, stars: starsById);
}

/// Per-activity completion for the logged-in user, from their session rooms:
/// completed = all of the user's role goals collected; in-progress = a joined
/// session that isn't complete; absent → not started. Same Matrix source as
/// [_userGoalTiers]; drives the completion filter.
Map<String, MapCompletionFilter> _userCompletion(Client client) {
  final m = <String, MapCompletionFilter>{};
  for (final room in client.rooms) {
    final activityId = room.activityId;
    if (activityId == null) continue;
    final role = room.ownRole;
    if (role == null) continue;
    final total = role.allGoals.length;
    final collected = room.ownCompletedGoals.length;
    final status = (total > 0 && collected >= total)
        ? MapCompletionFilter.completed
        : MapCompletionFilter.inProgress;
    final existing = m[activityId];
    if (existing == null || status.index > existing.index) {
      m[activityId] = status;
    }
  }
  return m;
}

/// CEFR levels at or below [level] — the personalized default band (attainable
/// + comfortable). Null level → all levels (no CEFR narrowing).
Set<LanguageLevelTypeEnum> _bandAtOrBelow(LanguageLevelTypeEnum? level) {
  if (level == null) return LanguageLevelTypeEnum.values.toSet();
  return LanguageLevelTypeEnum.values
      .where((l) => l.storageInt <= level.storageInt)
      .toSet();
}

/// The world map. In world_v2 a single instance is hosted persistently by
/// the app shell ([WorkspaceShell]) as the base layer every section
/// overlays — built once and never remounted on navigation, so tiles,
/// camera, and pins are preserved as you move around the nav.
///
/// Its content is scoped by [MapContextController]: World shows all pins; a
/// selected course shows only that quest's activities and the camera refits
/// to it. Pins are thin (id, title, point); tapping one opens a preview card
/// in place — its thin title shows immediately while the full plan loads
/// behind a shimmer. Star colour reflects Matrix-synced goal progress.
class WorldMap extends StatefulWidget {
  /// Optional camera override, e.g. to center on an activity's location.
  final LatLng? initialCenter;
  final double? initialZoom;

  /// Optional controller so parents can move the camera after build.
  final MapController? controller;

  /// Logical-pixel width of the nav-rail + left-column overlay the shell
  /// draws *on top* of this full-bleed map. A course camera-fit adds it as
  /// left padding so the fitted content lands in the uncovered area to the
  /// right of the overlay instead of behind it. 0 when nothing overlays it.
  final double leftOverlayWidth;

  /// Logical-pixel width of a right-docked overlay (the analytics panel). A
  /// course camera-fit adds it as right padding so the fitted content lands in
  /// the uncovered area to the left of the panel. 0 when nothing docks right.
  final double rightOverlayWidth;

  /// When set, the map brings this target into the exposed canvas (the area the
  /// left column and detail panel don't cover) instead of fitting the whole
  /// course — e.g. while an activity's `?activity=` detail panel is open. The
  /// focus kind is open: add a [MapFocus] subclass and one arm in
  /// [_WorldMapState._focusPoint] to focus new content (a location, an object).
  final MapFocus? focus;

  const WorldMap({
    super.key,
    this.initialCenter,
    this.initialZoom,
    this.controller,
    this.leftOverlayWidth = 0.0,
    this.rightOverlayWidth = 0.0,
    this.focus,
  });

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap>
    with SingleTickerProviderStateMixin {
  final MapController _ownController = MapController();
  MapController get _controller => widget.controller ?? _ownController;

  /// The activity pins currently shown — the active context's set (the whole
  /// world, or a selected quest's activities). Thin: id, title, point.
  List<QuestActivityCard> _pins = [];

  /// The activity a learner tapped to expand to its large card in place: a
  /// small/mid pin promotes to the large tier on tap, and the large card then
  /// taps through to the plan page. Null when nothing is promoted; tapping the
  /// empty map clears it. Stays on the persistent map — no navigation, no second
  /// map, no preview popup.
  String? _promotedActivityId;

  Client? _client;
  StreamSubscription<dynamic>? _syncSub;

  // Search + filter state (World context only). The personalized default is the
  // initial state — my L2 + at/below my CEFR — and search/filters refine it.
  String _query = '';
  bool _l2Only = true;
  Set<LanguageLevelTypeEnum> _cefrFilter = {};
  Set<LanguageLevelTypeEnum> _defaultCefr = {};
  final Set<MapCompletionFilter> _completionFilter = {};
  bool _filterDefaultsApplied = false;

  bool _loadingPins = false;
  Timer? _refetchDebounce;

  /// Debounce for context-driven camera fits: when you click through courses,
  /// the camera waits until you've settled (~2s) before gliding, rather than
  /// snapping on every hop. Re-armed on each request; only the last fires.
  Timer? _fitDebounce;
  static const Duration _fitSettleDelay = Duration(seconds: 2);

  /// The zoom the camera glides to when an activity is focused (opened) — close
  /// enough to read it as "this specific spot" (neighborhood/building level).
  static const double _focusZoom = 16.0;

  /// Drives the smooth camera glide (center + zoom tween) instead of an instant
  /// `fitCamera` snap. Retargets cleanly if a new fit lands mid-flight.
  AnimationController? _camAnim;
  CurvedAnimation? _camCurve;
  LatLng? _camStart;
  LatLng? _camTarget;
  double _camStartZoom = 0;
  double _camTargetZoom = 0;
  static const Duration _camGlideDuration = Duration(milliseconds: 600);

  /// Cached per-activity live signals (state + fill + recency + pinged),
  /// completion, and the learner's star total per activity, recomputed on room
  /// sync (not per frame) so the O(rooms) scan doesn't run every build.
  /// [_completion] backs the completion filter chip; [_userStars] feeds the
  /// progression gate built each frame in [build].
  Map<String, PinSignals> _signals = {};
  Map<String, int> _userStars = {};
  Map<String, MapCompletionFilter> _completion = {};

  /// Learning-objective ids across the learner's joined courses, for relevance
  /// banding. Rebuilt async on course join/leave.
  final JoinedObjectiveCache _objectiveCache = JoinedObjectiveCache();

  /// Activity ids with a recently-pinged open session (best-effort, scanned from
  /// joined course-space messages). Folded into [_signals].
  Set<String> _pingedActivityIds = {};

  /// Rotates which joinable activities occupy the large featured slots when more
  /// than the budget qualify (every 5s; see world-map.instructions.md).
  Timer? _rotationTimer;
  int _largeRotationIndex = 0;
  int _largePoolSize = 0; // set in build; gates the rotation tick
  static const int _largeBudget = 3;

  bool get _isWorld => MapContextController.notifier.value is! CourseMapContext;

  @override
  void initState() {
    super.initState();
    // Invariant: the shell owns a single persistent instance, so this runs
    // once per app session — section navigation overlays the map, never
    // remounts it.
    _camAnim = AnimationController(vsync: this, duration: _camGlideDuration)
      ..addListener(_onCamGlideTick);
    _camCurve = CurvedAnimation(parent: _camAnim!, curve: Curves.easeInOut);
    _loadForContext();
    MapContextController.notifier.addListener(_onContextChange);
    MapPinController.notifier.addListener(_onPinControllerChange);
    // Rotate the large featured slots when more joinable activities qualify than
    // the budget, so each gets airtime (world-map.instructions.md).
    _rotationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _largePoolSize > _largeBudget) {
        setState(() => _largeRotationIndex++);
      }
    });
    // Rebuild when a featured large card's full plan hydrates (image + goals).
    ActivityPlanRepo.instance.addListener(_onPlanHydrate);
  }

  void _onPlanHydrate() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recompute goal/completion state when the user collects a goal or joins a
    // session (room state sync) — recolours pins and updates the filter.
    final client = Matrix.of(context).client;
    if (_client != client) {
      _client = client;
      _recomputeProgress();
      // The objective set and pinged scan do network/timeline work, so they run
      // once on client set (not every sync). Joining a course mid-session
      // refreshes them on the next remount — acceptable staleness for now.
      _rebuildObjectiveCache(client);
      _recomputePinged(client);
      _syncSub?.cancel();
      _syncSub = client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 2))
          .listen((_) {
            if (mounted) _recomputeProgress();
          });
    }
    // Personalized default: my CEFR band (at/below my level). Applied once the
    // user controller is available.
    if (!_filterDefaultsApplied) {
      _filterDefaultsApplied = true;
      _defaultCefr = _bandAtOrBelow(
        MatrixState.pangeaController.userController.userCefrLevel,
      );
      _cefrFilter = {..._defaultCefr};
    }
  }

  void _recomputeProgress() {
    final client = _client;
    if (client == null) return;
    final derived = _deriveActivitySignals(
      client,
      pingedActivityIds: _pingedActivityIds,
    );
    final completion = _userCompletion(client);
    if (!mounted) {
      _signals = derived.signals;
      _userStars = derived.stars;
      _completion = completion;
      return;
    }
    setState(() {
      _signals = derived.signals;
      _userStars = derived.stars;
      _completion = completion;
    });
  }

  /// Rebuild the joined-course outlines (a few quest reads), reading each
  /// course's teacher override for the stars-to-unlock threshold, then re-rank.
  Future<void> _rebuildObjectiveCache(Client client) async {
    final courseRooms = client.rooms
        .where(
          (r) =>
              r.isSpace &&
              r.membership == Membership.join &&
              r.coursePlan != null,
        )
        .toList();
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
    );
    if (mounted) setState(() {}); // re-rank with the loaded outlines
  }

  /// Best-effort pinged detection: scan joined course spaces' recent messages
  /// for the host's recruit ping (carries `pangea.activity.id`), within a day.
  /// A ping leaves no persistent room state, so this proxy is intentionally
  /// approximate — its efficacy is worth watching (world-map.instructions.md).
  Future<void> _recomputePinged(Client client) async {
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
    if (!mounted ||
        (pinged.length == _pingedActivityIds.length &&
            pinged.containsAll(_pingedActivityIds))) {
      return;
    }
    _pingedActivityIds = pinged;
    setState(() {
      _signals = _deriveActivitySignals(
        client,
        pingedActivityIds: pinged,
      ).signals;
    });
  }

  @override
  void didUpdateWidget(covariant WorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-center when the focused activity changes or the exposed canvas resizes
    // (a panel opened/closed), so the selection stays in the visible map area.
    // A focus change is a deliberate target move (an activity opened) and glides
    // immediately; an overlay-width change is layout-driven (panels opening or
    // closing), so it debounces — rapid open/close coalesces into one settled
    // glide instead of jerking on every step. See routing.instructions.md.
    if (oldWidget.focus != widget.focus) {
      _fitToContext();
    } else if (oldWidget.leftOverlayWidth != widget.leftOverlayWidth ||
        oldWidget.rightOverlayWidth != widget.rightOverlayWidth) {
      _fitToContext(debounce: true);
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _rotationTimer?.cancel();
    _refetchDebounce?.cancel();
    _fitDebounce?.cancel();
    _camCurve?.dispose();
    _camAnim?.dispose();
    MapContextController.notifier.removeListener(_onContextChange);
    MapPinController.notifier.removeListener(_onPinControllerChange);
    ActivityPlanRepo.instance.removeListener(_onPlanHydrate);
    // Reset the process-global so a pin selected at teardown (e.g. logging out
    // with a pin sheet up) can't strand a stale `true` that would hide the bottom
    // nav at the bare map on the next mount. See `routing.instructions.md`.
    MapPinController.set(false);
    super.dispose();
  }

  /// The shell sets [MapPinController] false when the map is covered by a
  /// full-screen panel on a narrow screen (navigating to a section/detail), so a
  /// tapped-pin preview doesn't linger and keep the bottom nav hidden. Mirror
  /// that here — drop our own selection when the controller is cleared by anyone
  /// else. Guarded so our own clears (which also set it false) don't loop.
  void _onPinControllerChange() {
    if (!MapPinController.notifier.value &&
        _promotedActivityId != null &&
        mounted) {
      _collapse();
    }
  }

  void _onContextChange() {
    // Close any open preview when the map re-scopes (e.g. entering a course),
    // then reload pins for the new scope and refit. The camera fit is debounced
    // so clicking through courses doesn't snap the camera on every hop — it
    // glides only after you've settled on one.
    if (mounted) {
      setState(() => _promotedActivityId = null);
      MapPinController.set(false);
    }
    _loadForContext(debounceFit: true);
  }

  /// Load the pins for the active map context. A selected course shows that
  /// quest's activities (context-bound). World shows a personalized,
  /// viewport-bounded set via the bbox endpoint — that needs camera bounds, so
  /// the World load runs from [_loadWorldPins] (here when the camera is ready,
  /// and from onMapReady / onPositionChanged).
  Future<void> _loadForContext({bool debounceFit = false}) async {
    final mapContext = MapContextController.notifier.value;
    if (mapContext is CourseMapContext) {
      try {
        final pins = await QuestRepo.questPins(mapContext.coursePlanId);
        if (!mounted) return;
        setState(() => _pins = pins);
        _fitToContext(debounce: debounceFit);
      } catch (_) {
        // Map stays usable without activity pins.
      }
      return;
    }
    _loadWorldPins();
  }

  /// World pins for the current viewport, personalized to the user's language
  /// (unless widened) and localized to their L1. No-op until the camera is laid
  /// out (onMapReady retries). CEFR band, completion, and text search are
  /// applied client-side over the result via [_visiblePins].
  Future<void> _loadWorldPins() async {
    if (!_isWorld) return;
    final LatLngBounds bounds;
    try {
      bounds = _controller.camera.visibleBounds;
    } catch (_) {
      return; // camera not ready yet
    }
    final user = MatrixState.pangeaController.userController;
    if (mounted) setState(() => _loadingPins = true);
    try {
      final pins = await ActivityMapRepo.bboxPins(
        bounds: bounds,
        l2: _l2Only ? user.userL2Code : null,
        l1: user.userL1Code,
      );
      if (!mounted) return;
      setState(() {
        _pins = pins;
        _loadingPins = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPins = false);
    }
  }

  // ---- filtering ------------------------------------------------------------

  bool _cefrMatches(QuestActivityCard card) {
    final cefr = card.cefr;
    if (cefr == null || cefr.isEmpty) return true; // unknown level: keep
    final norm = cefr.toUpperCase().replaceAll('_', '');
    return _cefrFilter.any((l) => l.string == norm);
  }

  bool _completionMatches(QuestActivityCard card) {
    if (_completionFilter.isEmpty) return true;
    final status =
        _completion[card.activityId] ?? MapCompletionFilter.notStarted;
    return _completionFilter.contains(status);
  }

  /// The pins actually shown: the loaded set narrowed by the active CEFR band,
  /// completion filter, and free-text query. World only; a course shows its set.
  List<QuestActivityCard> get _visiblePins {
    if (!_isWorld) return _pins;
    return _pins
        .where(
          (c) =>
              _cefrMatches(c) &&
              _completionMatches(c) &&
              c.matchesQuery(_query),
        )
        .toList();
  }

  bool get _canReset =>
      _query.isNotEmpty ||
      !_l2Only ||
      _completionFilter.isNotEmpty ||
      _cefrFilter.length != _defaultCefr.length ||
      !_cefrFilter.containsAll(_defaultCefr);

  // ---- filter actions -------------------------------------------------------

  void _toggleL2() {
    setState(() => _l2Only = !_l2Only);
    _loadWorldPins(); // L2 changes the working set → re-fetch
  }

  void _toggleCefr(LanguageLevelTypeEnum level) {
    setState(() {
      if (!_cefrFilter.remove(level)) _cefrFilter.add(level);
    });
  }

  void _toggleCompletion(MapCompletionFilter c) {
    setState(() {
      if (!_completionFilter.remove(c)) _completionFilter.add(c);
    });
  }

  void _resetFilters() {
    final wasWidened = !_l2Only;
    setState(() {
      _query = '';
      _completionFilter.clear();
      _cefrFilter = {..._defaultCefr};
      _l2Only = true;
    });
    if (wasWidened) _loadWorldPins(); // L2 narrowed again → re-fetch
  }

  /// Fly to a search result and open its preview (the Maps-style result tap).
  /// A deliberate tap glides immediately and wins over any pending context fit.
  void _flyTo(QuestActivityCard card) {
    final point = card.point;
    if (point != null) {
      _fitDebounce?.cancel();
      try {
        _animateFit(
          CameraFit.coordinates(
            coordinates: [point],
            padding: EdgeInsets.fromLTRB(
              widget.leftOverlayWidth + 64,
              64,
              widget.rightOverlayWidth + 64,
              64,
            ),
            maxZoom: 13,
          ),
        );
      } catch (_) {}
    }
    _promoteToLarge(card);
  }

  /// Promote [card] to its large card in place: a small/mid pin expands to the
  /// large tier on tap (the large card then taps through to the plan page). The
  /// large marker hydrates the full plan itself (image + star total), so this
  /// only flips the tier. No navigation, no preview popup.
  void _promoteToLarge(QuestActivityCard card) {
    setState(() => _promotedActivityId = card.activityId);
    ActivityPlanRepo.instance.ensure(card.activityId);
  }

  void _collapse() {
    if (_promotedActivityId == null) return;
    setState(() => _promotedActivityId = null);
  }

  /// Resolve a [MapFocus] to a map coordinate, or null if not resolvable yet.
  /// Exhaustive over the sealed [MapFocus]: adding a focus kind makes this a
  /// compile error until its arm is added — that is the extension seam.
  LatLng? _focusPoint(MapFocus? focus) {
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

  /// Centers the current selection within the *exposed* canvas — the map area
  /// the left column and detail panel don't cover. A specifically-focused
  /// target centers on itself (keeping the current zoom); a course fits all
  /// its activities. Returning to World keeps the current view rather than
  /// yanking the camera. The move is an animated glide ([_animateFit]).
  ///
  /// [debounce]: when re-scoping by clicking through courses, wait until the
  /// user settles (~2s) before gliding, so the camera doesn't snap on every hop.
  /// Direct moves (a panel opening, a search-result tap) pass `false`.
  void _fitToContext({bool debounce = false}) {
    _fitDebounce?.cancel();
    if (!debounce) {
      _runFitToContext();
      return;
    }
    _fitDebounce = Timer(_fitSettleDelay, _runFitToContext);
  }

  void _runFitToContext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        // Inset the left edge by the overlay so content lands in the uncovered
        // area to the right of the column/panel, not behind it.
        final padding = EdgeInsets.fromLTRB(
          widget.leftOverlayWidth + 64.0,
          64.0,
          widget.rightOverlayWidth + 64.0,
          64.0,
        );

        // A specific focus target is zoomed IN on within the exposed canvas:
        // opening an activity glides the camera down to its pin at a close
        // (neighborhood/building) zoom, never zooming out past where we already
        // are. Today that is an activity; new focus kinds resolve in
        // [_focusPoint].
        final point = _focusPoint(widget.focus);
        if (point != null) {
          _animateFit(
            CameraFit.coordinates(
              coordinates: [point],
              padding: padding,
              maxZoom: _controller.camera.zoom > _focusZoom
                  ? _controller.camera.zoom
                  : _focusZoom,
            ),
          );
          return;
        }

        // Otherwise a course context fits all of its activities.
        if (MapContextController.notifier.value is! CourseMapContext) return;
        final points = _pins.map((c) => c.point).whereType<LatLng>().toList();
        if (points.isEmpty) return;
        _animateFit(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: padding,
            maxZoom: 12.0,
          ),
        );
      } catch (_) {
        // Controller/camera not ready yet; the next change will refit.
      }
    });
  }

  /// Glide the camera to where [fit] would place it (instead of snapping via
  /// `fitCamera`). [CameraFit.fit] resolves the target center+zoom without
  /// moving; we tween to it.
  void _animateFit(CameraFit fit) {
    final target = fit.fit(_controller.camera);
    _animateCameraTo(target.center, target.zoom);
  }

  /// Tween the camera center + zoom over [_camGlideDuration]. Re-targets cleanly
  /// if called mid-flight (the glide restarts from the current position).
  void _animateCameraTo(LatLng center, double zoom) {
    final anim = _camAnim;
    if (anim == null || !mounted) {
      try {
        _controller.move(center, zoom);
      } catch (_) {}
      return;
    }
    _camStart = _controller.camera.center;
    _camStartZoom = _controller.camera.zoom;
    _camTarget = center;
    _camTargetZoom = zoom;
    anim
      ..reset()
      ..forward();
  }

  void _onCamGlideTick() {
    final start = _camStart;
    final end = _camTarget;
    final curve = _camCurve;
    if (start == null || end == null || curve == null) return;
    final t = curve.value;
    final lat = start.latitude + (end.latitude - start.latitude) * t;
    final lng = start.longitude + (end.longitude - start.longitude) * t;
    final zoom = _camStartZoom + (_camTargetZoom - _camStartZoom) * t;
    try {
      _controller.move(LatLng(lat, lng), zoom);
    } catch (_) {
      // Camera not ready / disposed mid-tick.
    }
  }

  /// Open the activity detail in-place, preserving the current route (course
  /// stays selected, map stays put) via the `?activity=<id>` param. The detail
  /// panel fetches the full plan on open. Reached from the preview's "Details".
  void _openActivity(QuestActivityCard card) {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    // Open the activity plan as map content. Pin entry is UNSCOPED: drop the
    // `?m=course:` filter along with the left/right panels (the plan replaces the
    // left-primary surface) and add `activity=`. The absence of course scope is
    // what makes this a parentless overlay — its close is an X to the map, not a
    // back-arrow to a course card (a course-list tap keeps the scope and so gets
    // the back-arrow). The map still focuses the activity's pin via the
    // `activity=` param (`mapFocusFor` → `ActivityFocus`), independent of scope.
    // See `routing.instructions.md`.
    final parts = uri.query.isEmpty ? <String>[] : uri.query.split('&');
    parts.removeWhere(
      (p) =>
          p == 'left' ||
          p.startsWith('left=') ||
          p == 'right' ||
          p.startsWith('right=') ||
          p == 'm' ||
          p.startsWith('m=') ||
          p == 'activity' ||
          p.startsWith('activity=') ||
          p == 'autoplay' ||
          p.startsWith('autoplay='),
    );
    parts.add('activity=${card.activityId}');
    context.go(parts.isEmpty ? '/' : '/?${parts.join('&')}');
    _collapse();
  }

  /// The clustered-pins bubble (Google-Maps grouping), coloured by the cluster's
  /// dominant state so a cluster with an open session reads green.
  Widget _clusterBubble(
    BuildContext context,
    int count,
    ActivityPinState dominant,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: _stateColor(dominant),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  /// Small tier: a plain state-coloured dot (the long tail), with the gold
  /// progress fill. No glyph.
  Marker _smallDotMarker(
    QuestActivityCard card,
    LatLng point,
    ActivityPinState state,
    double fill,
  ) {
    return Marker(
      point: point,
      width: 18,
      height: 18,
      child: Tooltip(
        message: card.title,
        // Semantics below names the pin; exclude the Tooltip so the title isn't
        // announced twice ("<title> <title>"). See accessibility.instructions.md.
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: card.title,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => _promoteToLarge(card),
            child: _stateDot(
              state: state,
              diameter: 18,
              borderWidth: 1.5,
              fill: fill,
            ),
          ),
        ),
      ),
    );
  }

  /// Mid tier: a state-coloured pin with an activity glyph and the gold progress
  /// fill, plus a hand badge when the open session has been pinged.
  Marker _midPinMarker(
    QuestActivityCard card,
    LatLng point,
    ActivityPinState state,
    bool pinged,
    double fill,
  ) {
    return Marker(
      point: point,
      width: 44,
      height: 44,
      child: Tooltip(
        message: card.title,
        // Semantics below names the pin; exclude the Tooltip so the title isn't
        // announced twice ("<title> <title>").
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: card.title,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => _promoteToLarge(card),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                _stateDot(
                  state: state,
                  diameter: 36,
                  borderWidth: 2,
                  fill: fill,
                  glyph: const Icon(
                    Icons.chat_bubble_outline,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                if (pinged)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.back_hand,
                        size: 12,
                        color: Color(0xFF34A853),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The newest open joinable session for [activityId]: its joined non-bot
  /// participants (for the avatar stack) and its open-role count (the "?" slots).
  /// Empty when no such session is in the user's reachable rooms.
  ({List<LargeCardParticipant> participants, int openSlots}) _joinableInfo(
    Client client,
    String activityId,
  ) {
    Room? best;
    for (final r in client.rooms) {
      if (r.activityId != activityId) continue;
      if (!(r.numRemainingRoles > 0 && r.ownRoleState == null)) continue;
      final ms = r.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      final bestMs =
          best?.lastEvent?.originServerTs.millisecondsSinceEpoch ?? 0;
      if (best == null || ms > bestMs) best = r;
    }
    if (best == null) return (participants: const [], openSlots: 0);
    final participants = best
        .getParticipants()
        .where(
          (u) =>
              u.membership == Membership.join && u.id != BotName.byEnvironment,
        )
        .map<LargeCardParticipant>(
          (u) => (avatar: u.avatarUrl, name: u.calcDisplayname()),
        )
        .toList();
    return (participants: participants, openSlots: best.numRemainingRoles);
  }

  /// Large tier: the rich featured card (Figma `… Large`). The full plan (image +
  /// goal total) hydrates on demand for the few featured activities; the
  /// joinable form also shows the session's participants. See
  /// [WorldMapLargeCard] and world-map.instructions.md.
  Marker _largeCardMarker(
    QuestActivityCard card,
    LatLng point,
    ActivityPinState state,
    bool pinged,
  ) {
    final client = _client;
    // Hydrate the full plan for this featured card (no-op once cached); the
    // repo listener rebuilds the map when it lands.
    ActivityPlanRepo.instance.ensure(card.activityId);
    final plan = ActivityPlanRepo.instance.cachedPlan(card.activityId);
    final joinable = state == ActivityPinState.joinable;
    final info = (joinable && client != null)
        ? _joinableInfo(client, card.activityId)
        : (participants: const <LargeCardParticipant>[], openSlots: 0);
    return Marker(
      point: point,
      width: 260,
      // The inner Align lets the card hug its own content (each state is a
      // different height: locked has no star row, completed adds an action row,
      // joinable adds the avatar row). Height here is only a ceiling so the
      // tallest variant isn't clipped; shorter cards don't stretch to fill it.
      height: joinable ? 184 : 150,
      alignment: Alignment.topCenter,
      child: Align(
        alignment: Alignment.topCenter,
        child: WorldMapLargeCard(
          card: card,
          state: state,
          pinged: pinged,
          plan: plan,
          starsEarned: _userStars[card.activityId] ?? 0,
          participants: info.participants,
          openSlots: info.openSlots,
          onTap: () => _openActivity(card),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // world-map-tiles Phase 1: free hosted tiles switched by app theme —
    // OpenStreetMap (light) / CartoDB Dark Matter (dark).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final retina = dark && MediaQuery.devicePixelRatioOf(context) > 1.0;

    // The pins actually shown: the loaded set narrowed by the active
    // search/filters (World only; a course shows its set as-is).
    final visible = _visiblePins;

    // Auto-featured large cards render only where there is horizontal room
    // (desktop / column mode); a promoted card renders at any width.
    final narrow = !FluffyThemes.isColumnMode(context);
    final desktop = !narrow;
    // Rank the in-view pins into tiers (per-view budgets). Filter to the camera
    // bounds when available so promotion reflects what the learner is looking at.
    // Apply the learning-objective progression gate: a pin whose objectives are
    // all locked (gated, none unlocked) reads locked, unless it already has an
    // open joinable session. Built per frame from the loaded outlines + stars
    // (both cheap) so a star award or course change re-gates on the next build.
    final gate = buildLoGate(
      outlines: _objectiveCache.outlines,
      starsByActivity: _userStars,
    );
    final signals = <String, PinSignals>{};
    for (final card in visible) {
      final base = _signals[card.activityId] ?? const PinSignals();
      signals[card.activityId] =
          (base.state != ActivityPinState.joinable &&
              gate.isPinLocked(card.learningObjectiveRefs))
          ? PinSignals(
              state: ActivityPinState.locked,
              completionFraction: base.completionFraction,
              pinged: base.pinged,
              recency: base.recency,
            )
          : base;
    }
    List<QuestActivityCard> inView = visible;
    try {
      final bounds = _controller.camera.visibleBounds;
      inView = visible
          .where((c) => c.point != null && bounds.contains(c.point!))
          .toList();
    } catch (_) {
      // Camera not ready; rank the full filtered set.
    }
    final user = MatrixState.pangeaController.userController;
    final ranking = rankPins(
      inViewPins: inView,
      userL2: user.userL2Code,
      userCefr: user.userCefrLevel,
      joinedObjectiveIds: _objectiveCache.ids,
      signals: signals,
    );
    _largePoolSize = ranking.largePool.length;
    // The large featured cards (desktop only): a rotating window over the
    // joinable pool; pool members not currently featured render at mid weight.
    final largeWindow = <String>{};
    if (desktop && ranking.largePool.isNotEmpty) {
      final n = min(_largeBudget, ranking.largePool.length);
      for (var i = 0; i < n; i++) {
        largeWindow.add(
          ranking.largePool[(_largeRotationIndex + i) %
              ranking.largePool.length],
        );
      }
    }
    PinTier tierOf(String id) {
      // A tapped small/mid pin is promoted to its large card in place.
      if (id == _promotedActivityId) return PinTier.large;
      if (largeWindow.contains(id)) return PinTier.large;
      if (ranking.largePool.contains(id) || ranking.midIds.contains(id)) {
        return PinTier.mid;
      }
      return PinTier.small;
    }

    ActivityPinState stateOf(String id) =>
        signals[id]?.state ?? ActivityPinState.unlocked;
    bool pingedOf(String id) => signals[id]?.pinged ?? false;
    // The progress fill renders only on unlocked pins (the unlocked→finished
    // gradation); joinable and locked carry no fill.
    double fillOf(String id) {
      final s = signals[id];
      if (s == null || s.state != ActivityPinState.unlocked) return 0;
      return s.completionFraction;
    }

    final clusterStateByPoint = <LatLng, ActivityPinState>{
      for (final c in visible)
        if (c.point != null) c.point!: stateOf(c.activityId),
    };
    final map = FlutterMap(
      mapController: _controller,
      options: MapOptions(
        // The persistent instance keeps its own camera across navigation,
        // so no external camera-state restore is needed.
        initialCenter: widget.initialCenter ?? const LatLng(20, 0),
        initialZoom: widget.initialZoom ?? 3,
        // minZoom 3 (not 2): containLatitude rejects a move when the
        // constrained latitude band is shorter than the viewport, and the
        // ±90 band is only ~1024px tall at z2 — that would freeze *all*
        // panning on windows taller than ~1024px (common when maximized).
        // z3 gives a ~2048px band, clearing any realistic viewport.
        minZoom: 3,
        maxZoom: 18,
        // Clamp latitude only — leaving longitude free so the user can pan
        // east-west and the world wraps seamlessly ("rotate the world
        // around"). Epsg3857 replicates longitude, so tiles and markers
        // repeat across world copies automatically. A longitude-bounded
        // `contain`/`containCenter` pins the camera when zoomed out and hides
        // content behind the left column with no way to pan it out.
        cameraConstraint: const CameraConstraint.containLatitude(90, -90),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        // Tap empty map → collapse a promoted large card back to its pin.
        onTap: (_, _) {
          if (_promotedActivityId != null) _collapse();
        },
        // World pins are viewport-bounded: load once the camera is ready, then
        // re-load (debounced) as the user pans/zooms. Course pins are
        // context-bound and unaffected.
        onMapReady: () {
          if (_isWorld) _loadWorldPins();
        },
        onPositionChanged: (_, _) {
          if (!_isWorld) return;
          _refetchDebounce?.cancel();
          _refetchDebounce = Timer(
            const Duration(milliseconds: 500),
            _loadWorldPins,
          );
        },
      ),
      children: [
        // Base tiles, switched by app theme: OpenStreetMap (light) / CartoDB
        // Dark Matter (dark). Retina (@2x) keeps the dark basemap's small
        // labels sharp; CartoDB serves @2x, light (OSM) stays 1x.
        TileLayer(
          urlTemplate: dark
              ? 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          retinaMode: retina,
          userAgentPackageName: 'com.talktolearn.chat',
        ),
        // world_v2: activity pins by relevance tier + state. Small dots (the
        // long tail) and mid pins (promoted matches) are clustered for
        // Google-Maps de-overlap; the 1–3 large featured cards render
        // unclustered in the layer above so they're always visible.
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            maxClusterRadius: 48,
            size: const Size(40, 40),
            padding: const EdgeInsets.all(50),
            markers: visible
                .map((card) {
                  final point = card.point;
                  if (point == null) return null;
                  final tier = tierOf(card.activityId);
                  if (tier == PinTier.large) return null; // rendered above
                  final state = stateOf(card.activityId);
                  return tier == PinTier.mid
                      ? _midPinMarker(
                          card,
                          point,
                          state,
                          pingedOf(card.activityId),
                          fillOf(card.activityId),
                        )
                      : _smallDotMarker(
                          card,
                          point,
                          state,
                          fillOf(card.activityId),
                        );
                })
                .whereType<Marker>()
                .toList(),
            builder: (context, markers) {
              // Colour the bubble by the cluster's dominant (highest-ladder)
              // state.
              var dominant = ActivityPinState.locked;
              for (final m in markers) {
                final s = clusterStateByPoint[m.point];
                if (s != null && s.index > dominant.index) dominant = s;
              }
              return Semantics(
                button: true,
                label: '${markers.length} ${L10n.of(context).activities}',
                excludeSemantics: true,
                child: _clusterBubble(context, markers.length, dominant),
              );
            },
          ),
        ),
        // Large cards (unclustered, always visible): the 1–3 auto-featured cards
        // on desktop plus any pin promoted by a tap. tierOf gates the auto pool
        // to desktop, so on a narrow screen only a promoted card is large here.
        MarkerLayer(
          markers: visible
              .where(
                (c) => c.point != null && tierOf(c.activityId) == PinTier.large,
              )
              .map(
                (card) => _largeCardMarker(
                  card,
                  card.point!,
                  stateOf(card.activityId),
                  pingedOf(card.activityId),
                ),
              )
              .toList(),
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
            if (dark) TextSourceAttribution('CARTO', onTap: () {}),
          ],
        ),
      ],
    );

    // World gets the search + filter overlay; a course shows its plain map.
    if (!_isWorld) return map;
    final l2 = MatrixState.pangeaController.userController.userL2Code;
    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          top: 12,
          left: widget.leftOverlayWidth + 12,
          width: 360,
          child: WorldMapSearchOverlay(
            query: _query,
            onQueryChanged: (q) => setState(() => _query = q),
            l2Only: _l2Only,
            l2Label: l2?.toUpperCase(),
            onToggleL2: _toggleL2,
            selectedCefr: _cefrFilter,
            onToggleCefr: _toggleCefr,
            selectedCompletion: _completionFilter,
            onToggleCompletion: _toggleCompletion,
            results: visible,
            onResultTap: _flyTo,
            canReset: _canReset,
            onReset: _resetFilters,
            emptyInView: !_loadingPins && visible.isEmpty,
          ),
        ),
      ],
    );
  }
}
