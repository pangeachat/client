import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/activity_map_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_signals.dart';
import 'package:fluffychat/routes/world/world_map_view.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

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
///
/// Split controller/view (the codebase paradigm): [WorldMapController] owns the
/// State — pins, camera animation, search/filter state, and the room-sync
/// derivations — and [WorldMapView] is the stateless render that reads it.
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
  /// [WorldMapController._focusPoint] to focus new content (a location, an object).
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
  WorldMapController createState() => WorldMapController();
}

/// The world map's controller: all of its State (pins, camera glide, search /
/// filter state) plus the logic that maintains it (context loads, room-sync
/// progress derivations, camera fits). [build] returns the stateless
/// [WorldMapView], which reads this controller's view-facing accessors and routes
/// every interaction back to its methods. See world-map.instructions.md.
class WorldMapController extends State<WorldMap>
    with SingleTickerProviderStateMixin {
  final MapController _ownController = MapController();

  /// #7077: the OpenFreeMap dark vector style, loaded ONCE. A single Style read
  /// fans out to the tilejson, glyphs, and sprite; the dark base layer
  /// FutureBuilds on this and falls back to the CartoDB raster until it resolves
  /// (or if it errors), so dark mode is never blank. `late final` so it is
  /// created on first access only — i.e. only in dark mode.
  late final Future<Style> darkMapStyle = StyleReader(
    uri: 'https://tiles.openfreemap.org/styles/dark',
  ).read();

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
  /// progression gate built each frame in [WorldMapView].
  Map<String, PinSignals> _signals = {};
  Map<String, int> _userStars = {};
  Map<String, MapCompletionFilter> _completion = {};

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

  /// Activity ids with a recently-pinged open session (best-effort, scanned from
  /// joined course-space messages). Folded into [_signals].
  Set<String> _pingedActivityIds = {};

  /// Rotates which joinable activities occupy the large featured slots when more
  /// than the budget qualify (every 5s; see world-map.instructions.md).
  Timer? _rotationTimer;
  int _largeRotationIndex = 0;

  /// Size of the featured (joinable) pool, recorded by [WorldMapView] each build;
  /// the rotation tick only advances when it exceeds [largeBudget].
  int largePoolSize = 0;

  /// How many large featured cards show at once (desktop).
  static const int largeBudget = 3;

  // ---- View-facing accessors (read by WorldMapView) -------------------------

  /// The flutter_map controller (a caller-provided override, or our own). The
  /// view passes it to [FlutterMap] and reads its camera; the controller
  /// animates it.
  MapController get mapController => widget.controller ?? _ownController;

  bool get isWorld => MapContextController.notifier.value is! CourseMapContext;
  String? get promotedActivityId => _promotedActivityId;
  Client? get client => _client;
  bool get loadingPins => _loadingPins;
  Map<String, PinSignals> get signals => _signals;
  Map<String, int> get userStars => _userStars;
  Map<String, MapCompletionFilter> get completion => _completion;
  JoinedObjectiveCache get objectiveCache => _objectiveCache;
  int get largeRotationIndex => _largeRotationIndex;
  String get query => _query;
  bool get l2Only => _l2Only;
  Set<LanguageLevelTypeEnum> get cefrFilter => _cefrFilter;
  Set<MapCompletionFilter> get completionFilter => _completionFilter;

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
      if (mounted && largePoolSize > largeBudget) {
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
      // First build of the objective cache. It can come back empty if the
      // joined-course rooms / their outlines aren't ready yet — the sync listener
      // below rebuilds it when the joined-course set changes (or a prior build
      // resolved nothing), so banding + the gate recover within the session
      // instead of staying blank until a remount (which never happens for this
      // persistent map). The pinged scan does one-shot timeline work.
      _rebuildObjectiveCache(client);
      _recomputePinged(client);
      _syncSub?.cancel();
      _syncSub = client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 2))
          .listen((_) {
            if (!mounted) return;
            _recomputeProgress();
            _maybeRebuildObjectiveCache(client);
          });
    }
    // Personalized default: my CEFR band (at/below my level). Applied once the
    // user controller is available.
    if (!_filterDefaultsApplied) {
      _filterDefaultsApplied = true;
      _defaultCefr = bandAtOrBelow(
        MatrixState.pangeaController.userController.userCefrLevel,
      );
      _cefrFilter = {..._defaultCefr};
    }
  }

  void _recomputeProgress() {
    final client = _client;
    if (client == null) return;
    final derived = deriveActivitySignals(
      client,
      pingedActivityIds: _pingedActivityIds,
    );
    final completion = userCompletion(client);
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

  /// The learner's joined course spaces (a space they belong to that carries a
  /// course plan) — the source set for the objective cache + relevance banding.
  List<Room> _joinedCourseRooms(Client client) => client.rooms
      .where(
        (r) =>
            r.isSpace &&
            r.membership == Membership.join &&
            r.coursePlan != null,
      )
      .toList();

  /// Rebuild the joined-course outlines (a few quest reads), reading each
  /// course's teacher override for the stars-to-unlock threshold, then re-rank.
  /// Guarded so overlapping syncs don't stack rebuilds. A course whose outline
  /// fails to resolve is logged (not silently dropped): an empty cache means no
  /// relevance banding and a fail-open gate, which is otherwise invisible.
  Future<void> _rebuildObjectiveCache(Client client) async {
    if (_objectiveCacheRebuilding) return;
    _objectiveCacheRebuilding = true;
    try {
      final courseRooms = _joinedCourseRooms(client);
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
      if (mounted) setState(() {}); // re-rank with the loaded outlines
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
  void _maybeRebuildObjectiveCache(Client client) {
    if (_objectiveCacheRebuilding) return;
    final uuids = _joinedCourseRooms(
      client,
    ).map((r) => r.coursePlan!.uuid).toSet();
    final setChanged =
        uuids.length != _objectiveCacheUuids.length ||
        !uuids.containsAll(_objectiveCacheUuids);
    final emptyButHasCourses = _objectiveCache.ids.isEmpty && uuids.isNotEmpty;
    if (setChanged || emptyButHasCourses) _rebuildObjectiveCache(client);
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
      _signals = deriveActivitySignals(
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
      collapse();
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
  /// the World load runs from [loadWorldPins] (here when the camera is ready,
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
    loadWorldPins();
  }

  /// World pins for the current viewport, personalized to the user's language
  /// (unless widened) and localized to their L1. No-op until the camera is laid
  /// out (onMapReady retries). CEFR band, completion, and text search are
  /// applied client-side over the result via [visiblePins].
  Future<void> loadWorldPins() async {
    if (!isWorld) return;
    final LatLngBounds bounds;
    try {
      bounds = mapController.camera.visibleBounds;
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

  /// Debounced viewport reload, called by the view as the camera pans/zooms.
  /// Course pins are context-bound, so this is World-only.
  void handleMapPositionChanged() {
    if (!isWorld) return;
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(const Duration(milliseconds: 500), loadWorldPins);
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
  List<QuestActivityCard> get visiblePins {
    if (!isWorld) return _pins;
    return _pins
        .where(
          (c) =>
              _cefrMatches(c) &&
              _completionMatches(c) &&
              c.matchesQuery(_query),
        )
        .toList();
  }

  bool get canReset =>
      _query.isNotEmpty ||
      !_l2Only ||
      _completionFilter.isNotEmpty ||
      _cefrFilter.length != _defaultCefr.length ||
      !_cefrFilter.containsAll(_defaultCefr);

  // ---- filter actions -------------------------------------------------------

  void setQuery(String q) => setState(() => _query = q);

  void toggleL2() {
    setState(() => _l2Only = !_l2Only);
    loadWorldPins(); // L2 changes the working set → re-fetch
  }

  void toggleCefr(LanguageLevelTypeEnum level) {
    setState(() {
      if (!_cefrFilter.remove(level)) _cefrFilter.add(level);
    });
  }

  void toggleCompletion(MapCompletionFilter c) {
    setState(() {
      if (!_completionFilter.remove(c)) _completionFilter.add(c);
    });
  }

  void resetFilters() {
    final wasWidened = !_l2Only;
    setState(() {
      _query = '';
      _completionFilter.clear();
      _cefrFilter = {..._defaultCefr};
      _l2Only = true;
    });
    if (wasWidened) loadWorldPins(); // L2 narrowed again → re-fetch
  }

  /// Fly to a search result and open its preview (the Maps-style result tap).
  /// A deliberate tap glides immediately and wins over any pending context fit.
  void flyTo(QuestActivityCard card) {
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
    promoteToLarge(card);
  }

  /// Promote [card] to its large card in place: a small/mid pin expands to the
  /// large tier on tap (the large card then taps through to the plan page). The
  /// large marker hydrates the full plan itself (image + star total), so this
  /// only flips the tier. No navigation, no preview popup.
  void promoteToLarge(QuestActivityCard card) =>
      promoteToLargeById(card.activityId);

  /// As [promoteToLarge] but by id. The clustered small/mid markers route their
  /// tap here via the cluster layer's `onMarkerTap`: the marker-cluster package
  /// intercepts marker taps, so a marker's own `onTap` never fires for a pointer
  /// (it only centered the camera, the #7072 symptom). The tapped marker carries
  /// its activity id as its key, which is all promotion needs.
  void promoteToLargeById(String activityId) {
    setState(() => _promotedActivityId = activityId);
    ActivityPlanRepo.instance.ensure(activityId);
  }

  void collapse() {
    if (_promotedActivityId == null) return;
    setState(() => _promotedActivityId = null);
  }

  /// Glide back to the whole-world view (the initial camera). Pins, clusters,
  /// and search only ever zoom the camera IN, so this is the one explicit
  /// "zoom out to everything" affordance (#7086). Camera-only: the course scope
  /// and open panels are untouched.
  void resetToWorld() => _animateCameraTo(const LatLng(20, 0), 3.0);

  /// Step the zoom by [delta] levels around the current center, clamped to the
  /// map's range — backs the on-map +/- buttons, since a tap/search only ever
  /// zooms IN (#7086). Accumulates toward the in-flight glide target (not the
  /// mid-glide live zoom), so rapid clicks each advance a full level instead of
  /// under-shooting, and snaps to integer levels so the steps land crisply.
  void zoomBy(double delta) {
    final base = (_camAnim?.isAnimating ?? false)
        ? _camTargetZoom
        : mapController.camera.zoom;
    _animateCameraTo(
      mapController.camera.center,
      (base + delta).clamp(3.0, 18.0).roundToDouble(),
    );
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
              maxZoom: mapController.camera.zoom > _focusZoom
                  ? mapController.camera.zoom
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
    final target = fit.fit(mapController.camera);
    _animateCameraTo(target.center, target.zoom);
  }

  /// Tween the camera center + zoom over [_camGlideDuration]. Re-targets cleanly
  /// if called mid-flight (the glide restarts from the current position).
  void _animateCameraTo(LatLng center, double zoom) {
    final anim = _camAnim;
    if (anim == null || !mounted) {
      try {
        mapController.move(center, zoom);
      } catch (_) {}
      return;
    }
    _camStart = mapController.camera.center;
    _camStartZoom = mapController.camera.zoom;
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
      mapController.move(LatLng(lat, lng), zoom);
    } catch (_) {
      // Camera not ready / disposed mid-tick.
    }
  }

  /// Open the activity detail in-place, preserving the current route (course
  /// stays selected, map stays put) via the `?activity=<id>` param. The detail
  /// panel fetches the full plan on open. Reached from the preview's "Details".
  void openActivity(QuestActivityCard card) {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    // Open the activity plan as map content. Pin entry is UNSCOPED: drop the
    // `?m=course:` filter along with the left/right panels (the plan replaces the
    // left-primary surface) and add `activity=`. The absence of course scope is
    // what makes this a parentless overlay — its close is an X to the map, not a
    // back-arrow to a course card (a course-list tap keeps the scope and so gets
    // the back-arrow). The map still focuses the activity's pin via the
    // `activity=` param (`mapFocusFor` → `ActivityFocus`), independent of scope.
    // See `routing.instructions.md`.
    final parts = WorkspaceQuery.parts(uri.query);
    WorkspaceQuery.removeKeys(parts, {
      'left',
      'right',
      'm',
      'activity',
      'autoplay',
    });
    parts.add('activity=${card.activityId}');
    context.go(WorkspaceQuery.location('/', parts));
    collapse();
  }

  @override
  Widget build(BuildContext context) => WorldMapView(this);
}
