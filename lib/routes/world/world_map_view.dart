import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_cluster_bubble.dart';
import 'package:fluffychat/routes/world/world_map_constants.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The per-frame pin draw model resolved by [_WorldMapViewState._resolvePinRender]:
/// the visible set and, for each pin id, its tier / colour-state / pinged-badge /
/// progress-fill, plus the cluster dominant-state lookup. Lets the build method
/// read as composition (resolve the model, then lay out the marker layers).
class _PinRenderer {
  final List<QuestActivityCard> visible;
  final Map<String, double> activityIdToFill;
  final Map<String, ActivityPinState> activityIdToState;
  final Map<String, bool> activityIdToPingStatus;
  final Map<String, PinTier> activityIdToTier;

  /// Long-tail pins to drop from the cluster layer because they sit under a
  /// placed large card, so no count bubble ever forms beneath a card.
  final Set<String> suppressedIds;

  const _PinRenderer({
    required this.visible,
    required this.activityIdToFill,
    required this.activityIdToState,
    required this.activityIdToPingStatus,
    required this.activityIdToTier,
    required this.suppressedIds,
  });

  List<QuestActivityCard> get largeCards => visible
      .where((c) => c.point != null && tierOf(c.activityId) == PinTier.large)
      .toList();

  List<QuestActivityCard> get nonLargeCards => visible
      .where(
        (c) =>
            c.point != null &&
            tierOf(c.activityId) != PinTier.large &&
            !suppressedIds.contains(c.activityId),
      )
      .toList();

  Map<LatLng, ActivityPinState> get clusterStateByPoint =>
      <LatLng, ActivityPinState>{
        for (final c in visible)
          if (c.point != null) c.point!: stateOf(c.activityId),
      };

  // The progress fill is the activity's completion fraction at every colour
  // state — orthogonal to the colour, never hiding the pin (#7186).
  double fillOf(String id) => activityIdToFill[id] ?? 0;

  ActivityPinState stateOf(String id) =>
      activityIdToState[id] ?? ActivityPinState.unlocked;

  bool pingedOf(String id) => activityIdToPingStatus[id] ?? false;

  PinTier tierOf(String id) => activityIdToTier[id] ?? PinTier.small;
}

/// Cached render snapshot for a pin that is animating out of the active set.
class _PinSnapshot {
  final QuestActivityCard card;
  final ActivityPinState state;
  final PinTier tier;
  final bool pinged;
  final double fill;

  const _PinSnapshot({
    required this.card,
    required this.state,
    required this.tier,
    required this.pinged,
    required this.fill,
  });
}

/// The render of the persistent world map, driven by its [WorldMapController].
/// It reads the controller's cached signals / stars / pins / progression,
/// applies the per-frame single-score relevance ranking to pick each pin's tier
/// (small dot / mid pin / large featured card), and lays the pins, clusters,
/// basemap tiles, and (World only) the search-filter overlay over the map. All
/// interaction routes back to the controller (tap a pin → select, tap a card →
/// open the activity, filter → reload). No pin is ever locked (#7186). See
/// world-map.instructions.md.
class WorldMapView extends StatefulWidget {
  final WorldMapController controller;

  const WorldMapView(this.controller, {super.key});

  @override
  State<WorldMapView> createState() => _WorldMapViewState();
}

class _WorldMapViewState extends State<WorldMapView> {
  /// Pins that have left the active set and are animating to scale 0.
  final Map<String, _PinSnapshot> _exiting = {};

  /// Last-known render snapshot of each active non-large pin, used to seed
  /// [_exiting] with the correct visual state when a pin leaves.
  Map<String, _PinSnapshot> _lastActive = {};

  /// True while the camera is moving (gesture or programmatic). Cluster bubbles
  /// that appear during movement skip their entry animation and start at full
  /// scale, preventing the pop-in that occurs when zoom crosses a cluster
  /// threshold and membership changes produce new widget instances.
  bool _cameraMoving = false;
  Timer? _cameraStopTimer;

  void _onPositionChanged(bool hasGesture) {
    _cameraMoving = true;
    _cameraStopTimer?.cancel();
    _cameraStopTimer = Timer(
      const Duration(milliseconds: 300),
      () { _cameraMoving = false; },
    );
    widget.controller.onMapPositionChanged(hasGesture);
  }

  @override
  void dispose() {
    _cameraStopTimer?.cancel();
    super.dispose();
  }

  /// Detects newly-gone non-large pins and adds them to [_exiting] using their
  /// last-known render state. Pins promoted to large are excluded (still
  /// visible as a card). Called at the top of [build] before the marker layers
  /// are constructed — mutates tracking maps without calling setState.
  void _updateExiting(_PinRenderer render) {
    final currentNonLargeIds = {
      for (final c in render.nonLargeCards) c.activityId
    };
    final largeIds = {for (final c in render.largeCards) c.activityId};
    final allCurrentIds = {...currentNonLargeIds, ...largeIds};

    // Re-appeared in any tier: cancel any in-progress exit animation.
    _exiting.removeWhere((id, _) => allCurrentIds.contains(id));

    // Newly absent (not promoted to large): seed from last frame's snapshot.
    for (final entry in _lastActive.entries) {
      if (!allCurrentIds.contains(entry.key) &&
          !_exiting.containsKey(entry.key)) {
        _exiting[entry.key] = entry.value;
      }
    }

    // Refresh the snapshot for the next frame.
    _lastActive = {
      for (final card in render.nonLargeCards)
        card.activityId: _PinSnapshot(
          card: card,
          state: render.stateOf(card.activityId),
          tier: render.tierOf(card.activityId),
          pinged: render.pingedOf(card.activityId),
          fill: render.fillOf(card.activityId),
        ),
    };
  }

  /// Resolve the per-frame pin draw model: the visible set, and for each pin its
  /// tier / colour-state / pinged / fill, plus the cluster dominant-state lookup.
  /// Applies the single-score relevance ranking that assigns tiers (a static
  /// top-N large set + a mid set), rebuilt each frame from the controller's
  /// cached signals + progression so a star award re-ranks next build. See
  /// world-map.instructions.md.
  _PinRenderer _resolvePinRender(BuildContext context) {
    final visible = widget.controller.visiblePins;
    // No lock layering: the controller's signals pass through unchanged — nothing
    // is ever locked now, progression only ranks (#7186).
    final signals = widget.controller.signals;
    final ranking = _getRankings(visible: visible, signals: signals);

    // Auto-featured large cards exist only where there's horizontal room
    // (desktop / column mode); on a narrow screen only a tap-selected card goes
    // large. The placement pass fits the candidates' footprints to the screen
    // (no overlap, no edge spill, not under a panel) and reserves the selection
    // first — see world-map.instructions.md (pipeline step 4).
    final desktop = FluffyThemes.isColumnMode(context);
    final placement = _placeLarge(
      visible: visible,
      candidates: desktop ? ranking.ordered : const <String>[],
    );

    // Mid is the next-ranked slice below whatever actually took a large slot, so
    // a featured candidate that couldn't fit large drops to mid here.
    final largeIds = placement.largeIds.toSet();
    final mediumIds = ranking.ordered
        .where((id) => !largeIds.contains(id))
        .take(ranking.midBudget)
        .toSet();

    return _createPinRenderer(
      visible: visible,
      signals: signals,
      largeIds: largeIds,
      mediumIds: mediumIds,
      suppressedIds: placement.suppressedIds,
    );
  }

  /// Footprint-aware placement of the large cards (pipeline step 4): projects each
  /// candidate to the screen via the live camera and keeps only those whose card
  /// fits the visible safe area (viewport minus the left/right overlays) without
  /// overlapping one already placed; the tap-selection is reserved first. Falls
  /// back to the static top-N (+ selection) on the rare frame where the camera
  /// isn't laid out yet. Also returns the long-tail pins to drop from clustering.
  PlacementResult _placeLarge({
    required List<QuestActivityCard> visible,
    required List<String> candidates,
  }) {
    final selectedId = widget.controller.selectedActivityId;
    final pointById = <String, LatLng>{
      for (final c in visible) c.activityId: ?c.point,
    };
    try {
      final camera = widget.controller.mapController.camera;
      final size = camera.size;
      const margin = 12.0;
      final safeArea = Rect.fromLTRB(
        widget.controller.widget.leftOverlayWidth + margin,
        margin,
        size.width - widget.controller.widget.rightOverlayWidth - margin,
        size.height - margin,
      );
      return placeLargeCards(
        orderedCandidates: candidates,
        selectedId: selectedId,
        visibleIds: pointById.keys,
        screenOffsetOf: (id) {
          final p = pointById[id];
          return p == null ? null : camera.latLngToScreenOffset(p);
        },
        cardSize: Size(
          PinTier.large.dotWidth,
          PinTier.large.dotHeight(ActivityPinState.joinable),
        ),
        safeArea: safeArea,
      );
    } catch (_) {
      // Camera not laid out yet: static top-N + selection, no fit/suppression.
      // The next (camera-ready) frame does the real placement.
      return PlacementResult(
        largeIds: [
          ?selectedId,
          ...candidates.where((id) => id != selectedId).take(3),
        ],
        suppressedIds: const {},
      );
    }
  }

  RankingResult _getRankings({
    required List<QuestActivityCard> visible,
    required Map<String, PinSignals> signals,
  }) {
    // Rank only the in-view pins (camera bounds when available) so promotion
    // reflects what the learner is looking at.
    List<QuestActivityCard> inView = visible;
    try {
      final bounds = widget.controller.mapController.camera.visibleBounds;
      inView = visible
          .where((c) => c.point != null && bounds.contains(c.point!))
          .toList();
    } catch (_) {
      // Camera not ready; rank the full filtered set.
    }

    final user = MatrixState.pangeaController.userController;
    return rankPins(
      inViewPins: inView,
      userL2: user.userL2Code,
      userCefr: user.userCefrLevel,
      progression: widget.controller.progression,
      signals: signals,
    );
  }

  _PinRenderer _createPinRenderer({
    required List<QuestActivityCard> visible,
    required Map<String, PinSignals> signals,
    required Set<String> largeIds,
    required Set<String> mediumIds,
    required Set<String> suppressedIds,
  }) {
    final activityIds = visible.map((c) => c.activityId).toSet();

    final Map<String, PinTier> tiers = {};
    final Map<String, ActivityPinState> states = {};
    final Map<String, bool> pings = {};
    final Map<String, double> fills = {};

    for (final id in activityIds) {
      // Large = a selected peek or a featured card the placement pass fit on
      // screen (both are already in largeIds); the next-ranked are mid, rest
      // small.
      tiers[id] = largeIds.contains(id)
          ? PinTier.large
          : mediumIds.contains(id)
          ? PinTier.mid
          : PinTier.small;

      final signal = signals[id];
      states[id] = signal?.state ?? ActivityPinState.unlocked;
      pings[id] = signal?.pinged ?? false;
      // The progress fill is the completion fraction at every state (orthogonal
      // to the colour) — a finished pin shows a full fill, never a separate state.
      fills[id] = signal?.completionFraction ?? 0;
    }

    return _PinRenderer(
      visible: visible,
      activityIdToFill: fills,
      activityIdToPingStatus: pings,
      activityIdToState: states,
      activityIdToTier: tiers,
      suppressedIds: suppressedIds,
    );
  }

  /// The clustered small/mid pins (large cards render unclustered above). Skips
  /// pins with no point and any selected/featured large pin.
  List<Marker> _clusterMarkers(_PinRenderer render) =>
      render.nonLargeCards.map((card) {
        final state = render.stateOf(card.activityId);
        final tier = render.tierOf(card.activityId);

        return Marker(
          key: ValueKey(card.activityId),
          point: card.point!,
          width: tier.dotWidth,
          height: tier.dotHeight(state),
          child: WorldMapDot(
            key: ValueKey(card.activityId),
            card: card,
            state: state,
            tier: tier,
            onTap: () => widget.controller.selectActivity(card.activityId),
            pinged: render.pingedOf(card.activityId),
            fill: render.fillOf(card.activityId),
          ),
        );
      }).toList();

  /// Dying pins rendered in a separate unclustered layer so they don't inflate
  /// cluster counts or disturb the bubble colour while shrinking out.
  List<Marker> _exitingMarkers() => _exiting.values
      .where((p) => p.card.point != null)
      .map(
        (p) => Marker(
          key: ValueKey('exiting_${p.card.activityId}'),
          point: p.card.point!,
          width: p.tier.dotWidth,
          height: p.tier.dotHeight(p.state),
          child: WorldMapDot(
            key: ValueKey('exiting_${p.card.activityId}'),
            card: p.card,
            state: p.state,
            tier: p.tier,
            onTap: () {},
            pinged: p.pinged,
            fill: p.fill,
            dying: true,
            onExited: () {
              if (mounted) setState(() => _exiting.remove(p.card.activityId));
            },
          ),
        ),
      )
      .toList();

  /// The 1–3 large featured cards (desktop) plus any tap-selected card, rendered
  /// unclustered so they're always visible.
  List<Marker> _largeMarkers(_PinRenderer render) => render.largeCards.map((
    card,
  ) {
    // Hydrate the full plan for this featured card (no-op once cached); the
    // repo listener rebuilds the map when it lands.
    ActivityPlanRepo.instance.ensure(card.activityId);
    final plan = ActivityPlanRepo.instance.cachedPlan(card.activityId);

    final joinableActivity =
        widget.controller.client?.bestJoinableActivityInstance(
      card.activityId,
    );

    final state = render.stateOf(card.activityId);
    final tier = PinTier.large;

    return Marker(
      point: card.point!,
      width: tier.dotWidth,
      // The inner Align lets the card hug its own content (each state is a
      // different height: locked has no star row, completed adds an action row,
      // joinable adds the avatar row). Height here is only a ceiling so the
      // tallest variant isn't clipped; shorter cards don't stretch to fill it.
      height: tier.dotHeight(state),
      alignment: Alignment.topCenter,
      child: Align(
        alignment: Alignment.topCenter,
        child: WorldMapLargeCard(
          card: card,
          state: state,
          pinged: render.pingedOf(card.activityId),
          plan: plan,
          starsEarned:
              widget.controller.activityStarsEarned(card.activityId) ?? 0,
          participants: joinableActivity?.largeCardParticipants ?? [],
          openSlots: joinableActivity?.numRemainingRoles ?? 0,
          onTap: () => widget.controller.openActivity(card),
        ),
      ),
    );
  }).toList();

  @override
  Widget build(BuildContext context) {
    // world-map-tiles Phase 1: free hosted tiles switched by app theme —
    // OpenStreetMap (light) / CartoDB Dark Matter (dark).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final retina = dark && MediaQuery.devicePixelRatioOf(context) > 1.0;

    // Resolve which pins to draw and each one's tier/state/pinged/fill once per
    // frame, then lay out the layers from it.
    final render = _resolvePinRender(context);

    // Detect newly-gone pins before building the marker layers.
    _updateExiting(render);

    final clusterStateByPoint = render.clusterStateByPoint;

    final map = FlutterMap(
      mapController: widget.controller.mapController,
      options: MapOptions(
        // The persistent instance keeps its own camera across navigation,
        // so no external camera-state restore is needed.
        initialCenter:
            widget.controller.widget.initialCenter ?? const LatLng(20, 0),
        initialZoom: widget.controller.widget.initialZoom ?? 3,
        // minZoom 3 (not 2): containLatitude rejects a move when the
        // constrained latitude band is shorter than the viewport, and the
        // ±90 band is only ~1024px tall at z2 — that would freeze *all*
        // panning on windows taller than ~1024px (common when maximized).
        // z3 gives a ~2048px band, clearing any realistic viewport.
        minZoom: WorldMapConstants.minZoom,
        maxZoom: WorldMapConstants.maxZoom,
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
        // Tap empty map → collapse a selected large card back to its pin.
        onTap: (_, _) => widget.controller.deselectActivity(),
        // World pins are viewport-bounded: load once the camera is ready, then
        // re-load (debounced) as the user pans/zooms. Course pins are
        // context-bound and unaffected.
        onMapReady: widget.controller.loadWorldPins,
        onPositionChanged: (_, hasGesture) =>
            _onPositionChanged(hasGesture),
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
        // long tail) and mid pins (featured matches) are clustered for
        // Google-Maps de-overlap; the 1–3 large featured cards render
        // unclustered in the layer above so they're always visible.
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            // No convex-hull "zoom polygon" on cluster tap: the package default
            // draws a bright-green (0xFF00FF00) hull with a yellow border during
            // the zoom animation, which flashed between areas while loading
            // (#7068). The map uses a smooth camera glide, not the hull metaphor.
            showPolygon: false,
            maxClusterRadius: 48,
            size: const Size(40, 40),
            padding: const EdgeInsets.all(50),
            // The cluster package intercepts marker taps and routes them to
            // `onMarkerTap` — a marker's own child `onTap` never fires for a
            // pointer. Without this, a small/mid pin tap only ran
            // `centerMarkerOnClick`, so it recentered the camera and did nothing
            // else (#7072). Per the world-map design ("tap to select, tap again
            // to focus"), select the tapped pin → its large card in place; a group
            // bubble still zooms to de-cluster (`zoomToBoundsOnClick`). The pin
            // carries its activity id as its key. Select in place, no recenter.
            centerMarkerOnClick: false,
            onMarkerTap: (marker) {
              final key = marker.key;
              if (key is ValueKey<String>) {
                widget.controller.selectActivity(key.value);
              }
            },
            markers: _clusterMarkers(render),
            builder: (context, markers) {
              // Colour the bubble by the cluster's dominant (highest-ladder)
              // state — unlocked unless any member has a joinable open session.
              var dominant = ActivityPinState.unlocked;
              for (final m in markers) {
                final s = clusterStateByPoint[m.point];
                if (s != null && s.index > dominant.index) dominant = s;
              }
              // Stable key based on sorted constituent marker IDs: preserves
              // the bubble's AnimationController state across camera rebuilds
              // where membership hasn't changed, preventing spurious re-animation.
              final key = ValueKey(
                (markers
                      .map(
                        (m) => m.key is ValueKey<String>
                            ? (m.key as ValueKey<String>).value
                            : '',
                      )
                      .toList()
                  ..sort())
                    .join(','),
              );
              return Semantics(
                button: true,
                label: '${markers.length} ${L10n.of(context).activities}',
                excludeSemantics: true,
                child: WorldMapClusterBubble(
                  key: key,
                  count: markers.length,
                  dominant: dominant,
                  animate: !_cameraMoving,
                ),
              );
            },
          ),
        ),
        // Dying pins (unclustered) rendered below the large cards but outside
        // the cluster layer so they don't skew bubble counts while animating out.
        MarkerLayer(markers: _exitingMarkers()),
        // Large cards (unclustered, always visible): the 1–3 auto-featured cards
        // on desktop plus any pin promoted by a tap.
        MarkerLayer(markers: _largeMarkers(render)),
        RichAttributionWidget(
          // #7218: bottom-LEFT so the attribution and its expand popup don't sit
          // under the bottom-right zoom/World controls (where it was covered and
          // hard to read, especially in dark mode).
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
            if (dark) TextSourceAttribution('CARTO', onTap: () {}),
          ],
        ),
      ],
    );

    // The on-map zoom-out / World control (#7086): pins, clusters, and search
    // only zoom the camera IN, so this is the way back out. Pinned to the
    // viewport bottom-right and kept there when a right panel opens (#7166): the
    // 88px cluster gutter reserved beside the right column leaves room, so the
    // controls no longer slide left with the panel. (rightOverlayWidth still pads
    // the camera fit in world_map.dart so focal content lands in the uncovered
    // area; only this on-map chrome stays fixed.) Shown on world and course maps.
    final controls = Positioned(
      right: 12,
      bottom: 28,
      child: _MapZoomControls(controller: widget.controller),
    );

    // A course shows its plain map (plus the controls); the world map adds the
    // search + filter overlay.
    if (!widget.controller.isWorld) {
      return Stack(
        children: [
          Positioned.fill(child: map),
          controls,
        ],
      );
    }
    final l2 = MatrixState.pangeaController.userController.userL2Code;
    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          top: 12,
          left: widget.controller.widget.leftOverlayWidth + 12,
          width: 360,
          child: WorldMapSearchOverlay(
            filter: widget.controller.filter,
            updateQuery: widget.controller.setQuery,
            l2Label: l2?.toUpperCase(),
            onToggleL2: widget.controller.toggleL2,
            onWidenSearch: () => widget.controller.resetFilters(l2Only: false),
            toggleCefr: widget.controller.toggleCefr,
            toggleCompletion: widget.controller.toggleCompletion,
            results: render.visible,
            onResultTap: widget.controller.flyTo,
            onReset: widget.controller.resetFilters,
            emptyInView:
                !widget.controller.loadingPins && render.visible.isEmpty,
          ),
        ),
        controls,
      ],
    );
  }
}

/// The on-map zoom controls (#7086): a small bottom-right stack with a World
/// reset (the one obvious "zoom out to everything", since pins/clusters/search
/// only ever zoom the camera IN) and +/- zoom steps. Camera-only — it never
/// changes the open panels or the course scope.
class _MapZoomControls extends StatelessWidget {
  final WorldMapController controller;

  const _MapZoomControls({required this.controller});

  /// The live camera zoom, or null before the map is laid out (reading the
  /// camera throws until then) — null leaves both step buttons enabled.
  double? _currentZoom() {
    try {
      return controller.mapController.camera.zoom;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Material(
      elevation: 2.0,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8.0),
      // Re-evaluate the +/- enabled state as the camera zooms (pinch, scroll,
      // or the glide) so each button greys out at its limit (#7171). Scoped to
      // this small stack via the map event stream rather than a full-view
      // rebuild; the World reset stays enabled (it re-centers, not just zooms).
      child: StreamBuilder(
        stream: controller.mapController.mapEventStream,
        builder: (context, _) {
          final zoom = _currentZoom();
          final canZoomIn = zoom == null || WorldMapConstants.canZoomIn(zoom);
          final canZoomOut = zoom == null || WorldMapConstants.canZoomOut(zoom);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.public),
                tooltip: l10n.resetMapView,
                onPressed: controller.resetToWorld,
              ),
              Divider(height: 1.0, color: theme.colorScheme.outlineVariant),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: l10n.zoomIn,
                onPressed: canZoomIn ? () => controller.zoomBy(1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.remove),
                tooltip: l10n.zoomOut,
                onPressed: canZoomOut ? () => controller.zoomBy(-1) : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
