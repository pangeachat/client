import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_constants.dart';
import 'package:fluffychat/routes/world/world_map_dismissals.dart';
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

  /// Logical-pixel height of a bottom overlay — the narrow activity-plan
  /// sheet at its half-rest state. A focus pan adds it as bottom padding so
  /// the focused pin centers in the exposed map ABOVE the sheet instead of
  /// behind it (#7640). 0 when nothing covers the bottom.
  final double bottomOverlayHeight;

  /// Logical-pixel width of the map actually visible between the open side panels
  /// (viewport − left overlay − right overlay). Drives the pin-density budget
  /// ([budgetForWidth]) — how many pins show and how many are large cards — so as
  /// panels open the map thins toward dots. See world-map.instructions.md.
  final double availableVisibleMapWidth;

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
    this.bottomOverlayHeight = 0.0,
    this.availableVisibleMapWidth = 0.0,
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

  /// Coalesces a burst of activity-plan hydrations (many pins resolve their
  /// plans at once) into a single signal recompute, so a session flips to its
  /// joinable/joined colour once its seats are known — notably an invited
  /// session, whose role count is unknown until its plan lands from CMS.
  Timer? _planHydrateDebounce;

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

  /// Activities the learner explicitly dismissed from the large-card tier (the
  /// card's X, #7207). A dismissed pin stays fully eligible for mid/small — the
  /// X demotes, it never removes — and without this memory the very next
  /// re-rank would just re-promote the card. Dismissals lapse after
  /// [WorldMapDismissals.ttl] so an X is never a permanent burial (#7245).
  final WorldMapDismissals _dismissals = WorldMapDismissals();

  /// Re-ranks the pins the moment the earliest dismissal lapses, so a card can
  /// return on an otherwise idle map (no pan/zoom/sync to trigger a rebuild).
  Timer? _dismissalExpiryTimer;

  /// Read by the view's tier pass and ranking: these ids never render large
  /// and carry the `dismissed` score penalty while their TTL runs.
  Set<String> get dismissedLargeIds => _dismissals.activeIds(DateTime.now());

  /// True while the camera is actively moving — a pan, pinch, scroll-wheel,
  /// double-tap, rotate, or a programmatic glide. The view freezes every pin/
  /// card's tier and size for the duration instead of recomputing against the
  /// live, still-moving camera bounds, so nothing flickers between tiers
  /// mid-gesture
  bool get isActivelyMoving => _moveSettleTimer?.isActive ?? false;
  Timer? _moveSettleTimer;
  StreamSubscription<MapEvent>? _mapEventSub;

  bool _loadingPins = false;
  Timer? _refetchDebounce;

  @override
  void initState() {
    super.initState();
    _cameraAnimationController = AnimationController(
      vsync: this,
      duration: WorldMapConstants.camGlideDuration,
    )..addListener(_onCamGlideTick);

    _mapEventSub = mapController.mapEventStream.listen(_onMapEvent);

    _loadForContext();

    MapContextController.notifier.addListener(_onContextChange);
    MapCameraFocusRequests.notifier.addListener(_onCameraFocusRequest);

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
      // persistent map). The pinged scan runs here and on sync (below) — it
      // surfaces recruit pings on the map and clears each course space's stuck
      // ping badge once consumed (#7366).
      _rebuildObjectiveCache(client);
      _recomputePinged(client);
      _discoverCoursemateSessions(client);
      _syncSub?.cancel();
      _syncSub = client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 2))
          .listen((_) {
            if (!mounted) return;
            _recomputeProgress();
            _maybeRebuildObjectiveCache(client);
            _recomputePinged(client);
            _discoverCoursemateSessions(client);
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

  /// The last activity the camera centred on ([focusedActivityId])
  String? _lastFocusedActivityId;

  @override
  void didUpdateWidget(covariant WorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-center when the focused activity changes or the exposed canvas resizes
    // (a panel opened/closed), so the selection stays in the visible map area.
    // A focus change is a deliberate target move (an activity opened, or a
    // session resumed into its room) and glides immediately; an overlay-width
    // change is layout-driven (panels opening or closing), so it debounces —
    // rapid open/close coalesces into one settled glide instead of jerking on
    // every step. See routing.instructions.md.
    //
    // The focus token stays null when resuming into a live room (a `room:`
    // token, #7257), so compare the *resolved* focused id ([focusedActivityId],
    // which reads that room back to its activity) — not just [widget.focus].
    final resolvedId = focusedActivityId;
    if (oldWidget.focus != widget.focus ||
        resolvedId != _lastFocusedActivityId) {
      _lastFocusedActivityId = resolvedId;
      _fitToContext();
    } else if (oldWidget.leftOverlayWidth != widget.leftOverlayWidth ||
        oldWidget.rightOverlayWidth != widget.rightOverlayWidth ||
        oldWidget.bottomOverlayHeight != widget.bottomOverlayHeight) {
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
    _planHydrateDebounce?.cancel();
    _dismissalExpiryTimer?.cancel();
    _moveSettleTimer?.cancel();
    _mapEventSub?.cancel();
    _cameraAnimationController.dispose();
    MapContextController.notifier.removeListener(_onContextChange);
    MapCameraFocusRequests.notifier.removeListener(_onCameraFocusRequest);
    ActivityPlanRepo.instance.removeListener(_onPlanHydrate);
    // Reset the process-global so a pin selected at teardown (e.g. logging out
    // with a pin sheet up) can't strand a stale `true` that would hide the bottom
    // nav at the bare map on the next mount. See `routing.instructions.md`.
    WorldMapPinsManager.set(false);
    super.dispose();
  }

  MapController get mapController => widget.controller ?? _ownController;

  bool get isWorld => MapContextController.notifier.value is! CourseMapContext;

  /// The id of the activity the detail panel is focused on, or null. Focus is
  /// the persistent "I'm working with this one" state (its panel is open and the
  /// camera settled on it); it drives a distinct focus marker on the pin at
  /// whatever tier it sits, and survives zoom/pan, clearing only when the panel
  /// closes or another activity is focused. Derived from [widget.focus] (the
  /// `?activity=` token via `mapFocusFor`), falling back to [_roomPanelActivityId]
  /// for a resumed session, so it auto-clears when the focus signal changes. See
  /// world-map.instructions.md ("Focus").
  String? get focusedActivityId =>
      focusedActivityIdOf(widget.focus) ?? _roomPanelActivityId;

  /// The activity behind an open room panel, when that room is one of the
  /// learner's own activity sessions — the "resume" path opens the live
  /// chat as a `room:` token, not an `activity:` one, so [widget.focus] is null
  /// there. Resolving the room back to its activity keeps the pin focused (glow)
  /// and the camera centred on it, so a resumed session behaves like any other
  /// selection. Null when no room panel is open or the room isn't an activity session / isn't known to the client yet.
  String? get _roomPanelActivityId {
    try {
      final roomId = activeRoomIdFromPanels(
        GoRouter.of(context).routeInformationProvider.value.uri,
      );
      if (roomId == null) return null;
      return client?.getRoomById(roomId)?.activityId;
    } catch (_) {
      return null;
    }
  }

  MapFocus? get _focusForCamera {
    final id = focusedActivityId;
    return id == null ? null : ActivityFocus(id);
  }

  /// The activity id a [MapFocus] focuses, or null for a non-activity / absent
  /// focus. Pure so the focus-marker resolution is unit-testable without pumping
  /// the map (#7349). Exhaustive over the sealed [MapFocus]: a new focus kind
  /// that isn't an activity simply yields null here.
  @visibleForTesting
  static String? focusedActivityIdOf(MapFocus? focus) => switch (focus) {
    ActivityFocus(:final activityId) => activityId,
    _ => null,
  };

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

  /// Activity ids the learner has earned at least one star in — the trail the
  /// ranking reserves slots for (world-map.instructions.md, "Goal Progress").
  Set<String> get progressedActivityIds => _pinsManager.progressedActivityIds;

  /// The learner has **no first activity yet** (never started, joined, or
  /// finished one) — the condition under which the ranking deprioritizes 3+ role
  /// activities (#7435). Cheap read over `client.rooms`, once per (debounced)
  /// re-rank. Null client → false (no penalty).
  bool get isNewLearner => _client?.hasAnyActivitySession == false;

  void _onPlanHydrate() {
    // A plan landing from CMS fires no room sync, so the sync-driven recompute
    // never re-derives seats for it — why an invited session (its role count
    // known only once the plan hydrates) never flips to joinable. Recompute the
    // signals, debounced so a burst of hydrations coalesces into one pass.
    _planHydrateDebounce?.cancel();
    _planHydrateDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _recomputeProgress();
    });
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

  Future<void> _discoverCoursemateSessions(Client client) async {
    await _pinsManager.discoverCoursemateSessions(client);
    // Discovery refreshes the extra joinable facts; re-derive signals so a
    // newly found coursemate session colours its pin.
    if (mounted) _recomputeProgress();
  }

  void _onContextChange() {
    // Reset the map-pin global and reload pins when the map re-scopes (e.g.
    // entering a course), then refit. The camera fit is debounced so clicking
    // through courses doesn't snap the camera on every hop — it glides only after
    // you've settled on one.
    if (mounted) {
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
          // The joined course's per-Mission activity pin scopes this view's
          // markers (org quests doc, client#7748); not joined / unset → null →
          // unrestricted.
          final courseRoom = Matrix.of(context).client.joinedCourseRooms
              .firstWhereOrNull(
                (r) => r.coursePlan?.uuid == mapContext.coursePlanId,
              );
          await _pinsManager.loadCourseScopedPins(
            mapContext.coursePlanId,
            pinnedActivitiesByObjective:
                courseRoom?.teacherMode.pinnedActivitiesByObjective,
          );

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
            ? _filterState.filter.l2?.langCodeShort
            : null,
        l1: user.userL1?.langCodeShort,
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

  /// The minimal screen translation that brings [card] fully inside [safe]: zero
  /// on an axis where it already fits, otherwise just enough to clear the
  /// overflowing edge. If [card] is larger than [safe] on an axis, aligns its low
  /// edge (top/left) so the header stays visible rather than zooming (#7155).
  ///
  /// Retained as the vestigial edge-nudge geometry: the maps-like redesign routes
  /// a tap straight to focus (which glides the camera onto the pin via
  /// [_fitToContext]), so nothing calls this in-app today. Kept per design (the
  /// edge-nudge is retained but seldom needed — world-map.instructions.md).
  @visibleForTesting
  static Offset minimalShiftToFit(Rect card, Rect safe) {
    double axis(double lo, double hi, double safeLo, double safeHi) {
      if (lo < safeLo) return safeLo - lo;
      if (hi > safeHi) return safeHi - hi;
      return 0;
    }

    return Offset(
      axis(card.left, card.right, safe.left, safe.right),
      axis(card.top, card.bottom, safe.top, safe.bottom),
    );
  }

  /// Fly to a search result and focus it (the Maps-style result tap): open its
  /// detail panel, which glides the camera onto its pin via the focus fit. One
  /// step — a deliberate tap goes straight to focus, no peek.
  void flyTo(QuestActivityCard card) => openActivity(card);

  /// Glide back to the whole-world view (the initial camera). Pins and search
  /// only ever zoom the camera IN, so this is the one explicit "zoom out to
  /// everything" affordance (#7086). Camera-only: the course scope, focus, and
  /// open panels are untouched.
  void resetToWorld() {
    _animateCameraTo(const LatLng(20, 0), minZoom);
  }

  /// The viewport-derived zoom-out floor (#7813, [WorldMapConstants.minZoomFor])
  /// for the map's current size, or the safe fallback before the map has laid
  /// out (reading the camera throws until then).
  double get minZoom {
    try {
      return WorldMapConstants.minZoomFor(mapController.camera.nonRotatedSize);
    } catch (_) {
      return WorldMapConstants.fallbackMinZoom;
    }
  }

  /// Step the zoom by [delta] levels around the current center, clamped to the
  /// map's range — backs the on-map +/- buttons, since a tap/search only ever
  /// zooms IN (#7086). Accumulates toward the in-flight glide target (not the
  /// mid-glide live zoom), so rapid clicks each advance a full level instead of
  /// under-shooting, and snaps to integer levels so the steps land crisply.
  /// Rounds BEFORE clamping: the floor is fractional (#7813), and rounding a
  /// clamped value could land back below it.
  void zoomBy(double delta) {
    final base = _cameraAnimationController.isAnimating
        ? _camTargetZoom
        : mapController.camera.zoom;

    _animateCameraTo(
      mapController.camera.center,
      (base + delta).roundToDouble().clamp(minZoom, WorldMapConstants.maxZoom),
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
        // A specific focus target PANS into the exposed canvas at the current
        // zoom — a pure glide, no zoom change in either direction (#7496: the
        // zoom-to-16 jump was disorienting). The single-point fit resolves the
        // center within the padded area; capping maxZoom at the current zoom
        // pins the zoom in place. Today that is an activity; new focus kinds
        // resolve in [_focusPoint].
        final point = _pinsManager.focusPoint(_focusForCamera);
        if (point != null) {
          _animateFit(
            CameraFit.coordinates(
              coordinates: [point],
              padding: _exposedCanvasPadding,
              maxZoom: mapController.camera.zoom,
            ),
          );
          return;
        }

        // A course coming into context moves the camera NOT AT ALL (#7616):
        // neither the old zoomful bounds fit nor the pan-to-top-pin tried
        // after it read as intentional — there is no single right place to
        // point at, and any auto-move was disorienting. The scope change
        // speaks through the pins; the camera goes to the course only via
        // the explicit focus button ([_onCameraFocusRequest]).
      } catch (_) {
        // Controller/camera not ready yet; the next change will refit.
      }
    });
  }

  /// Inset the left/right edges by the overlays so camera targets land in the
  /// uncovered map area beside the column/panel, not behind it.
  EdgeInsets get _exposedCanvasPadding => EdgeInsets.fromLTRB(
    widget.leftOverlayWidth + 64.0,
    64.0,
    widget.rightOverlayWidth + 64.0,
    widget.bottomOverlayHeight + 64.0,
  );

  /// The focus button (#7616) — the ONE camera path that zooms. A focused
  /// activity glides in to [WorldMapConstants.focusZoom] (never zooming out
  /// past the current view); a course context zoom+pan-fits all its
  /// activities' bounds. Fired via [MapCameraFocusRequests] from the activity
  /// plan page and the course card header.
  void _onCameraFocusRequest() {
    if (!mounted) return;
    try {
      final point = _pinsManager.focusPoint(_focusForCamera);
      if (point != null) {
        _animateFit(
          CameraFit.coordinates(
            coordinates: [point],
            padding: _exposedCanvasPadding,
            maxZoom: mapController.camera.zoom > WorldMapConstants.focusZoom
                ? mapController.camera.zoom
                : WorldMapConstants.focusZoom,
          ),
        );
        return;
      }

      if (MapContextController.notifier.value is! CourseMapContext) return;
      final points = _pinsManager.focusPoints;
      if (points.isEmpty) return;
      _animateFit(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: _exposedCanvasPadding,
          maxZoom: WorldMapConstants.courseFitMaxZoom,
        ),
      );
    } catch (_) {
      // Controller/camera not ready yet; the button can simply be pressed again.
    }
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
    // Pan longitude along the shortest angular direction so a pin near the
    // antimeridian glides toward its visible on-screen position (#7880).
    final lng = WorldMapConstants.lerpLongitude(
      start.longitude,
      end.longitude,
      p.pan,
    );
    final zoom = _camStartZoom + (_camTargetZoom - _camStartZoom) * p.zoom;
    try {
      mapController.move(LatLng(lat, lng), zoom);
    } catch (_) {
      // Camera not ready / disposed mid-tick.
    }
  }

  /// Called by the view as the camera moves. World pins re-fetch for the new
  /// viewport (debounced); course pins are context-bound. Focus is unaffected by
  /// pan/zoom — it persists until the panel closes (world-map.instructions.md).
  /// Movement-freeze tracking ([isActivelyMoving]) is driven separately by
  /// [_onMapEvent], not this callback, so it also covers a fling's coasting
  /// frames and programmatic glides (which fire `MapEventMove` without a
  /// matching `hasGesture`).
  void onMapPositionChanged(bool hasGesture) {
    if (!isWorld) return;
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(
      const Duration(milliseconds: 500),
      _onCameraSettled,
    );
  }

  /// One camera-settle pass: re-fetch the viewport's pins AND kick a (self-
  /// throttled) live-session discovery + signal recompute. Without the kick the
  /// matrix's live facts refresh only off sync ticks, so the viewport you pan
  /// to could rank against several-seconds-stale facts — the sluggish re-rank
  /// while scrolling around.
  void _onCameraSettled() {
    loadWorldPins();
    final client = _client;
    if (client != null) _discoverCoursemateSessions(client);
  }

  /// Flags [isActivelyMoving] on any camera-movement event (pan, zoom, rotate,
  /// gesture or programmatic), clearing it one settle interval after the last
  /// one — at which point the rebuild re-derives every pin/card's tier for the
  /// new camera instead of the frozen last-settled one (#7245). Applies in
  /// every map context (world and course), unlike the world-only re-fetch
  /// above.
  void _onMapEvent(MapEvent event) {
    final wasMoving = isActivelyMoving;
    _moveSettleTimer?.cancel();
    _moveSettleTimer = Timer(WorldMapConstants.moveSettle, () {
      if (mounted) setState(() {});
    });
    if (!wasMoving && mounted) setState(() {});
  }

  /// Open the activity detail in-place, preserving the current route (map stays
  /// put) as a `left=activity:` panel token, which also focuses the pin. The
  /// panel fetches the full plan on open. This is the one-step tap target: any
  /// pin tap (dot / card) and a search-result tap route here (no peek).
  void openActivity(QuestActivityCard card) {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    // Seat the activity as the sole left token via the nav helper — no raw
    // query surgery in feature code (routing.instructions.md). The course
    // context is kept: a pin on a course-scoped map closes back to the course,
    // a pin on the world map has none and closes with an X. A held session
    // resumes via the token's session-binding field (#7257). The map focuses
    // the activity's pin via the token (`mapFocusFor` → `ActivityFocus`).
    final myRoom = client?.activeActivityInstance(card.activityId);
    context.go(
      WorkspaceNav.openActivity(uri, card.activityId, roomId: myRoom?.id),
    );
  }

  /// The large card's X (#7207): demote this activity out of the large tier
  /// for [WorldMapDismissals.ttl] — it re-renders at whatever lighter tier it
  /// earns (mid where eligible, else a dot), never disappearing from the map,
  /// and returns to large contention when the TTL lapses (#7245). If the
  /// dismissed card is the focused one, the X also clears focus (drops the
  /// activity panel token, same as the panel's own close) so an open panel never
  /// points at a non-large pin.
  void dismissLargeCard(QuestActivityCard card) {
    setState(() => _dismissals.dismiss(card.activityId, DateTime.now()));
    _armDismissalExpiryTimer();
    if (focusedActivityId == card.activityId) {
      final uri = GoRouter.of(context).routeInformationProvider.value.uri;
      context.go(WorkspaceNav.dropActivityOverlay(uri));
    }
  }

  /// Re-rank when the earliest dismissal lapses; re-armed then for the next
  /// one, so each expiry surfaces its card even on an idle map.
  void _armDismissalExpiryTimer() {
    _dismissalExpiryTimer?.cancel();
    final expiry = _dismissals.nextExpiry(DateTime.now());
    if (expiry == null) return;
    _dismissalExpiryTimer = Timer(expiry.difference(DateTime.now()), () {
      if (mounted) setState(() {});
      _armDismissalExpiryTimer();
    });
  }

  @override
  Widget build(BuildContext context) => WorldMapView(this);
}
