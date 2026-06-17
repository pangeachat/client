import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/repo/activity_map_repo.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/map_context.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// How many of an activity's goals the current user has collected, across all
/// of their sessions of it. Drives the pin's star colour on the world map.
enum _GoalTier { none, some, all }

/// Pin star colour for a goal tier: gray = none collected, bronze = some,
/// gold = all (world_v2 progress affordance).
Color _starColor(_GoalTier tier) {
  switch (tier) {
    case _GoalTier.all:
      return AppConfig.gold;
    case _GoalTier.some:
      return const Color(0xFFCD7F32); // bronze
    case _GoalTier.none:
      return Colors.grey;
  }
}

/// Build `activityId -> best goal tier` from the user's own activity-session
/// rooms. Per session, the tier is measured against *the user's own role's*
/// goals ("by that particular user"): collected via the
/// `orchestrator_awarded_goals` room state. Activities the user hasn't started
/// (or that have no goals) are absent → they default to [_GoalTier.none]
/// (gray). Multiple sessions of one activity keep the highest tier reached.
///
/// This is the "completion data, stored in Matrix and automatically synced"
/// that colours the pins before any click — no CMS read needed for it.
Map<String, _GoalTier> _userGoalTiers(Client client) {
  final tiers = <String, _GoalTier>{};
  for (final room in client.rooms) {
    final activityId = room.activityId;
    if (activityId == null) continue;
    final role = room.ownRole;
    if (role == null) continue;
    final total = role.allGoals.length;
    if (total == 0) continue;
    final collected = room.ownCompletedGoals.length;
    final tier = collected <= 0
        ? _GoalTier.none
        : (collected >= total ? _GoalTier.all : _GoalTier.some);
    final existing = tiers[activityId];
    if (existing == null || tier.index > existing.index) {
      tiers[activityId] = tier;
    }
  }
  return tiers;
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
/// the app shell ([TwoColumnLayout]) as the base layer every section
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

  /// The pin whose preview popup is open (tapping a star selects it; tapping
  /// the map background or the popup's close clears it). Stays on the
  /// persistent map — no navigation, no second map.
  QuestActivityCard? _selectedActivity;

  /// The selected activity's full plan, fetched lazily on tap. Null while the
  /// fetch is in flight (the preview shows a shimmer) and when none is open.
  ActivityPlanModel? _selectedPlan;

  /// True while the selected activity's full plan is loading (drives the
  /// shimmer vs. the loaded card in the preview).
  bool _planLoading = false;

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

  /// Drives the smooth camera glide (center + zoom tween) instead of an instant
  /// `fitCamera` snap. Retargets cleanly if a new fit lands mid-flight.
  AnimationController? _camAnim;
  CurvedAnimation? _camCurve;
  LatLng? _camStart;
  LatLng? _camTarget;
  double _camStartZoom = 0;
  double _camTargetZoom = 0;
  static const Duration _camGlideDuration = Duration(milliseconds: 600);

  /// Cached per-activity goal tier + completion, recomputed on room sync (not
  /// per frame) so the O(rooms) scan doesn't run every build.
  Map<String, _GoalTier> _goalTiers = {};
  Map<String, MapCompletionFilter> _completion = {};

  bool get _isWorld =>
      MapContextController.notifier.value is! CourseMapContext;

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
    final tiers = _userGoalTiers(client);
    final completion = _userCompletion(client);
    if (!mounted) {
      _goalTiers = tiers;
      _completion = completion;
      return;
    }
    setState(() {
      _goalTiers = tiers;
      _completion = completion;
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
    _refetchDebounce?.cancel();
    _fitDebounce?.cancel();
    _camCurve?.dispose();
    _camAnim?.dispose();
    MapContextController.notifier.removeListener(_onContextChange);
    super.dispose();
  }

  void _onContextChange() {
    // Close any open preview when the map re-scopes (e.g. entering a course),
    // then reload pins for the new scope and refit. The camera fit is debounced
    // so clicking through courses doesn't snap the camera on every hop — it
    // glides only after you've settled on one.
    if (mounted) {
      setState(() {
        _selectedActivity = null;
        _selectedPlan = null;
        _planLoading = false;
      });
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
    _selectActivity(card);
  }

  /// Open the preview for [card] immediately, then fetch its full plan in the
  /// background (the preview shimmers until it arrives).
  Future<void> _selectActivity(QuestActivityCard card) async {
    setState(() {
      _selectedActivity = card;
      _selectedPlan = null;
      _planLoading = true;
    });
    try {
      final plan = await QuestRepo.activity(card.activityId);
      if (!mounted || _selectedActivity?.activityId != card.activityId) return;
      setState(() {
        _selectedPlan = plan;
        _planLoading = false;
      });
    } catch (_) {
      if (mounted && _selectedActivity?.activityId == card.activityId) {
        setState(() => _planLoading = false);
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedActivity = null;
      _selectedPlan = null;
      _planLoading = false;
    });
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

        // A specific focus target is brought into the exposed canvas at the
        // current zoom. Today that is an activity (centered on its pin); new
        // focus kinds resolve in [_focusPoint].
        final point = _focusPoint(widget.focus);
        if (point != null) {
          _animateFit(
            CameraFit.coordinates(
              coordinates: [point],
              padding: padding,
              maxZoom: _controller.camera.zoom,
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
    context.go(
      uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'activity': card.activityId,
        },
      ).toString(),
    );
    _clearSelection();
  }

  /// The clustered-pins bubble (Google-Maps grouping of nearby stars).
  Widget _clusterBubble(BuildContext context, int count) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cached per-activity goal progress (recomputed on sync, not per frame).
    final goalTiers = _goalTiers;
    // world-map-tiles Phase 1: free hosted tiles switched by app theme —
    // OpenStreetMap (light) / CartoDB Dark Matter (dark).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final retina = dark && MediaQuery.devicePixelRatioOf(context) > 1.0;

    // The pins actually shown: the loaded set narrowed by the active
    // search/filters (World only; a course shows its set as-is).
    final visible = _visiblePins;

    // Place the preview above the pin, but flip it below when the pin is too
    // near the top to fit (edge-aware, no map move).
    final selected = _selectedActivity;
    final selectedVisible =
        selected != null &&
        selected.point != null &&
        visible.any((c) => c.activityId == selected.activityId);
    bool popupAbove = true;
    if (selectedVisible) {
      try {
        popupAbove =
            _controller.camera.latLngToScreenOffset(selected.point!).dy > 360.0;
      } catch (_) {
        // Camera not ready yet; default to above.
      }
    }

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
        // Tap empty map → dismiss any open activity preview.
        onTap: (_, _) {
          if (_selectedActivity != null) _clearSelection();
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
        // world_v2: activities as star pins coloured by the user's goal
        // progress, clustered (Google-Maps de-overlap). Tapping a pin opens an
        // in-place preview; tapping a cluster zooms in.
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            maxClusterRadius: 48,
            size: const Size(40, 40),
            padding: const EdgeInsets.all(50),
            markers: visible
                .map((card) {
                  final point = card.point;
                  if (point == null) return null;
                  return Marker(
                    point: point,
                    width: 36,
                    height: 36,
                    child: Tooltip(
                      message: card.title,
                      child: GestureDetector(
                        onTap: () => _selectActivity(card),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _starColor(
                              goalTiers[card.activityId] ?? _GoalTier.none,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(blurRadius: 4, color: Colors.black38),
                            ],
                          ),
                          child: const Icon(
                            Icons.star,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                })
                .whereType<Marker>()
                .toList(),
            builder: (context, markers) =>
                _clusterBubble(context, markers.length),
          ),
        ),
        // Preview popup for the tapped activity — a marker so it stays glued to
        // its pin as the map moves. Opens immediately with the thin title; the
        // full plan loads behind a shimmer. No navigation; the map stays put.
        if (selectedVisible)
          MarkerLayer(
            markers: [
              Marker(
                point: selected.point!,
                width: 230,
                height: 400,
                alignment: popupAbove
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: _ActivityPreviewPopup(
                  card: selected,
                  plan: _selectedPlan,
                  loading: _planLoading,
                  below: !popupAbove,
                  onClose: _clearSelection,
                  onDetails: () => _openActivity(selected),
                ),
              ),
            ],
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

/// In-map preview popup for a tapped activity pin. Opens immediately: the
/// activity card renders the moment the full plan is available, and shows a
/// shimmer skeleton (with the title we already have from the pin) while it
/// loads. Plus a "Details" action — all without leaving the current view.
class _ActivityPreviewPopup extends StatelessWidget {
  final QuestActivityCard card;
  final ActivityPlanModel? plan;
  final bool loading;
  final bool below;
  final VoidCallback onClose;
  final VoidCallback onDetails;

  const _ActivityPreviewPopup({
    required this.card,
    required this.plan,
    required this.loading,
    required this.onClose,
    required this.onDetails,
    this.below = false,
  });

  static const double _cardWidth = 180.0;
  static const double _cardHeight = 262.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activity = plan;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Gap sits between the card and the pin — on top when the card hangs
        // below the pin, on the bottom when it floats above.
        if (below) const SizedBox(height: 14.0),
        Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16.0),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _cardWidth,
                  height: _cardHeight,
                  child: activity != null
                      ? ActivitySuggestionCard(
                          activity: activity,
                          width: _cardWidth,
                          height: _cardHeight,
                          fontSize: 16.0,
                          fontSizeSmall: 11.0,
                          iconSize: 11.0,
                        )
                      : _PreviewSkeleton(title: card.title, loading: loading),
                ),
                const SizedBox(height: 6.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: L10n.of(context).close,
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_full, size: 14),
                      label: Text(L10n.of(context).details),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onDetails,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!below) const SizedBox(height: 14.0),
      ],
    );
  }
}

/// Card-shaped placeholder shown while the full plan loads: the real title
/// (known from the pin) over a shimmering image block + meta line, matching
/// the [ActivitySuggestionCard] layout so the swap-in is seamless. When
/// [loading] is false but no plan arrived, it just holds the title (no
/// shimmer) rather than spinning forever.
class _PreviewSkeleton extends StatelessWidget {
  final String title;
  final bool loading;

  const _PreviewSkeleton({required this.title, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget block(double width, double height) {
      final box = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6.0),
        ),
      );
      if (!loading) return box;
      return Shimmer.fromColors(
        baseColor: theme.colorScheme.surfaceContainerHigh,
        highlightColor: theme.colorScheme.surfaceBright,
        child: box,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        color: theme.colorScheme.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(_ActivityPreviewPopup._cardWidth, 150.0),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 6.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16.0),
                    ),
                    block(90.0, 12.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
