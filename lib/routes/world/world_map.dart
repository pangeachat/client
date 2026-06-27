import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_query.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_constants.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';
import 'package:fluffychat/routes/world/world_map_pins_manager.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
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

  /// Debounce for context-driven camera fits: when you click through courses,
  /// the camera waits until you've settled (~2s) before gliding, rather than
  /// snapping on every hop. Re-armed on each request; only the last fires.
  Timer? _fitDebounce;

  /// Drives the smooth camera glide (center + zoom tween) instead of an instant
  /// `fitCamera` snap. Retargets cleanly if a new fit lands mid-flight.
  late final AnimationController _cameraAnimationController;
  LatLng? _camStart;
  LatLng? _camTarget;
  double _camStartZoom = 0;
  double _camTargetZoom = 0;

  Client? _client;

  StreamSubscription<dynamic>? _syncSub;
  StreamSubscription? _languageSubscription;
  StreamSubscription? _cefrLevelSubscription;

  final WorldMapFilterState _filterState = WorldMapFilterState();
  final WorldMapPinsManager _pinsManager = WorldMapPinsManager();

  bool _loadingPins = false;
  Timer? _refetchDebounce;

  @override
  void initState() {
    super.initState();
    _cameraAnimationController = AnimationController(
      vsync: this,
      duration: WorldMapConstants.camGlideDuration,
    )..addListener(_onCamGlideTick);

    _loadForContext();

    MapContextController.notifier.addListener(_onContextChange);
    WorldMapPinsManager.notifier.addListener(_onPinControllerChange);

    // Rebuild when a featured large card's full plan hydrates (image + goals).
    ActivityPlanRepo.instance.addListener(_onPlanHydrate);

    final user = MatrixState.pangeaController.userController;

    _languageSubscription?.cancel();
    _languageSubscription = user.languageStream.stream.listen((update) {
      if (update.targetLang != _filterState.filter.l2) {
        _setL2(update.targetLang);
      }
    });

    _cefrLevelSubscription?.cancel();
    _cefrLevelSubscription = user.settingsUpdateStream.stream.listen((update) {
      if (!_filterState.filter.cefrFilter.contains(
        update.userSettings.cefrLevel,
      )) {
        _setCefrLevel(update.userSettings.cefrLevel);
      }
    });
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
    if (!_filterState.filter.filterDefaultsApplied) {
      final l2 = MatrixState.pangeaController.userController.userL2;
      final cefr = MatrixState.pangeaController.userController.userCefrLevel;
      _filterState.applyDefaults(l2: l2, cefrLevel: cefr);
    }
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
    _languageSubscription?.cancel();
    _cefrLevelSubscription?.cancel();
    _refetchDebounce?.cancel();
    _fitDebounce?.cancel();
    _cameraAnimationController.dispose();
    MapContextController.notifier.removeListener(_onContextChange);
    WorldMapPinsManager.notifier.removeListener(_onPinControllerChange);
    ActivityPlanRepo.instance.removeListener(_onPlanHydrate);
    // Reset the process-global so a pin selected at teardown (e.g. logging out
    // with a pin sheet up) can't strand a stale `true` that would hide the bottom
    // nav at the bare map on the next mount. See `routing.instructions.md`.
    WorldMapPinsManager.set(false);
    super.dispose();
  }

  MapController get mapController => widget.controller ?? _ownController;

  bool get isWorld => MapContextController.notifier.value is! CourseMapContext;
  String? get promotedActivityId => _pinsManager.promotedActivityId;
  Client? get client => _client;
  bool get loadingPins => _loadingPins;

  WorldMapFilter get filter => _filterState.filter;
  Map<String, PinSignals> get signals => _pinsManager.signals;
  ProgressionResolution get progression => _pinsManager.progression;

  /// The pins actually shown: the loaded set narrowed by the active CEFR band,
  /// completion filter, and free-text query. World only; a course shows its set.
  List<QuestActivityCard> get visiblePins => _pinsManager.filteredPins((c) {
    if (!isWorld) return true;

    final status = _pinsManager.activityCompletionStatus(c.activityId);
    return _filterState.include(c, status ?? MapCompletionFilter.notStarted);
  });

  int? activityStarsEarned(String activityId) =>
      _pinsManager.activityStarsEarned(activityId);

  void _onPlanHydrate() {
    if (mounted) setState(() {});
  }

  void _recomputeProgress() {
    final client = _client;
    if (client == null) return;
    _pinsManager.recomputeProgress(client);
    if (mounted) setState(() {});
  }

  Future<void> _rebuildObjectiveCache(Client client) async {
    await _pinsManager.rebuildObjectiveCache(client);
    if (mounted) setState(() {});
  }

  Future<void> _maybeRebuildObjectiveCache(Client client) async {
    if (_pinsManager.shouldRebuildObjectiveCache(client)) {
      return _rebuildObjectiveCache(client);
    }
  }

  /// Best-effort pinged detection: scan joined course spaces' recent messages
  /// for the host's recruit ping (carries `pangea.activity.id`), within a day.
  /// A ping leaves no persistent room state, so this proxy is intentionally
  /// approximate — its efficacy is worth watching (world-map.instructions.md).
  Future<void> _recomputePinged(Client client) async {
    await _pinsManager.recomputePinged(client);
    if (mounted) setState(() {});
  }

  /// The shell sets [MapPinController] false when the map is covered by a
  /// full-screen panel on a narrow screen (navigating to a section/detail), so a
  /// tapped-pin preview doesn't linger and keep the bottom nav hidden. Mirror
  /// that here — drop our own selection when the controller is cleared by anyone
  /// else. Guarded so our own clears (which also set it false) don't loop.
  void _onPinControllerChange() {
    if (!WorldMapPinsManager.notifier.value && mounted) {
      demoteActivity();
    }
  }

  void _onContextChange() {
    // Close any open preview when the map re-scopes (e.g. entering a course),
    // then reload pins for the new scope and refit. The camera fit is debounced
    // so clicking through courses doesn't snap the camera on every hop — it
    // glides only after you've settled on one.
    if (mounted) {
      demoteActivity();
      WorldMapPinsManager.set(false);
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
    switch (mapContext) {
      case CourseMapContext():
        _ensureScopedCourseOutline(mapContext.coursePlanId);
        try {
          await _pinsManager.loadCourseScopedPins(mapContext.coursePlanId);

          if (!mounted) return;
          setState(() {});

          _fitToContext(debounce: debounceFit);
        } catch (_) {
          // Map stays usable without activity pins.
        }
        return;
      case WorldMapContext():
        _pinsManager.resetScopedCourseOutline();
        loadWorldPins();
        return;
    }
  }

  /// Resolve the viewed course's outline for a course-scoped map so the band
  /// ranks toward that course's next Mission even before the learner joins it
  /// (Will's decision). Skipped when the course is already a joined course (its
  /// outline is in the objective cache) or already resolved for this scope.
  Future<void> _ensureScopedCourseOutline(String coursePlanId) async {
    await _pinsManager.ensureScopedCourseOutline(coursePlanId);
    if (mounted) setState(() {});
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
      await _pinsManager.loadWorldScopedPins(
        bounds: bounds,
        l2: _filterState.filter.l2Only
            ? _filterState.filter.l2?.langCode
            : null,
        l1: user.userL1Code,
      );
    } finally {
      if (mounted) setState(() => _loadingPins = false);
    }
  }

  void setQuery(String q) => setState(() => _filterState.setQuery(q));

  void _setL2(LanguageModel? l2) {
    setState(() => _filterState.setL2(l2));
    loadWorldPins();
  }

  void _setCefrLevel(LanguageLevelTypeEnum? cefrLevel) =>
      setState(() => _filterState.setCefrLevel(cefrLevel));

  void toggleL2() {
    setState(() => _filterState.toggleL2());
    loadWorldPins(); // L2 changes the working set → re-fetch
  }

  void toggleCefr(LanguageLevelTypeEnum level) =>
      setState(() => _filterState.toggleCefr(level));

  void toggleCompletion(MapCompletionFilter c) =>
      setState(() => _filterState.toggleCompletion(c));

  void resetFilters({bool l2Only = true}) {
    final toggleL2Only = _filterState.filter.l2Only != l2Only;
    setState(() {
      _filterState.resetFilters(l2Only: l2Only);
    });

    if (toggleL2Only) {
      loadWorldPins(); // L2 narrowed again → re-fetch
    }
  }

  /// As [promoteToLarge] but by id. The clustered small/mid markers route their
  /// tap here via the cluster layer's `onMarkerTap`: the marker-cluster package
  /// intercepts marker taps, so a marker's own `onTap` never fires for a pointer
  /// (it only centered the camera, the #7072 symptom). The tapped marker carries
  /// its activity id as its key, which is all promotion needs.
  void promoteActivity(String activityId) {
    final promoted = _pinsManager.promoteActivity(activityId);
    if (promoted) setState(() {});
    ActivityPlanRepo.instance.ensure(activityId);
  }

  void demoteActivity() {
    final demoted = _pinsManager.demoteActivity();
    if (demoted) setState(() {});
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
    promoteActivity(card.activityId);
  }

  /// Glide back to the whole-world view (the initial camera). Pins, clusters,
  /// and search only ever zoom the camera IN, so this is the one explicit
  /// "zoom out to everything" affordance (#7086). Camera-only: the course scope
  /// and open panels are untouched.
  void resetToWorld() =>
      _animateCameraTo(const LatLng(20, 0), WorldMapConstants.minZoom);

  /// Step the zoom by [delta] levels around the current center, clamped to the
  /// map's range — backs the on-map +/- buttons, since a tap/search only ever
  /// zooms IN (#7086). Accumulates toward the in-flight glide target (not the
  /// mid-glide live zoom), so rapid clicks each advance a full level instead of
  /// under-shooting, and snaps to integer levels so the steps land crisply.
  void zoomBy(double delta) {
    final base = _cameraAnimationController.isAnimating
        ? _camTargetZoom
        : mapController.camera.zoom;

    _animateCameraTo(
      mapController.camera.center,
      (base + delta)
          .clamp(WorldMapConstants.minZoom, WorldMapConstants.maxZoom)
          .roundToDouble(),
    );
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
    _fitDebounce = Timer(WorldMapConstants.fitSettleDelay, _runFitToContext);
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
        final point = _pinsManager.focusPoint(widget.focus);
        if (point != null) {
          _animateFit(
            CameraFit.coordinates(
              coordinates: [point],
              padding: padding,
              maxZoom: mapController.camera.zoom > WorldMapConstants.focusZoom
                  ? mapController.camera.zoom
                  : WorldMapConstants.focusZoom,
            ),
          );
          return;
        }

        // Otherwise a course context fits all of its activities.
        if (MapContextController.notifier.value is! CourseMapContext) return;

        final points = _pinsManager.focusPoints;
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

  /// Tween the camera center + zoom to the target. The glide length scales with
  /// the zoom distance ([WorldMapConstants.glideDurationFor]) and pan/zoom are
  /// staggered so the pan runs at the wider zoom (#7239). Re-targets cleanly if
  /// called mid-flight (the glide restarts from the current position).
  void _animateCameraTo(LatLng center, double zoom) {
    final anim = _cameraAnimationController;
    if (!mounted) {
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
      ..duration = WorldMapConstants.glideDurationFor(_camStartZoom, zoom)
      ..reset()
      ..forward();
  }

  void _onCamGlideTick() {
    final start = _camStart;
    final end = _camTarget;
    if (start == null || end == null) return;

    // Stagger pan and zoom so the pan runs at the wider zoom (#7239).
    final p = WorldMapConstants.glideProgress(
      _cameraAnimationController.value,
      _camStartZoom,
      _camTargetZoom,
    );
    final lat = start.latitude + (end.latitude - start.latitude) * p.pan;
    final lng = start.longitude + (end.longitude - start.longitude) * p.pan;
    final zoom = _camStartZoom + (_camTargetZoom - _camStartZoom) * p.zoom;
    try {
      mapController.move(LatLng(lat, lng), zoom);
    } catch (_) {
      // Camera not ready / disposed mid-tick.
    }
  }

  /// Debounced viewport reload, called by the view as the camera pans/zooms.
  /// Course pins are context-bound, so this is World-only.
  void onMapPositionChanged() {
    if (!isWorld) return;
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(const Duration(milliseconds: 500), loadWorldPins);
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
      'roomid',
    });

    parts.add('activity=${card.activityId}');
    // #7257: if the learner already holds a started/joined session for this
    // activity, bind the overlay to that room (`roomid=`) so the start page
    // resumes it (selectRole/confirmedRole) instead of offering a fresh
    // instance. Pin entry stays unscoped — only the session room is added.
    final myRoom = client?.myActivityInstance(card.activityId);
    if (myRoom != null) {
      parts.add('roomid=${shortRoomId(myRoom.id)}');
    }
    context.go(WorkspaceQuery.location('/', parts));
    demoteActivity();
  }

  @override
  Widget build(BuildContext context) => WorldMapView(this);
}
