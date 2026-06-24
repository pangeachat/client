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
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The per-frame pin draw model resolved by [WorldMapView._resolvePinRender]:
/// the visible set and, for each pin id, its tier / colour-state / pinged-badge /
/// progress-fill, plus the cluster dominant-state lookup. Lets the build method
/// read as composition (resolve the model, then lay out the marker layers).
class _PinRenderer {
  final List<QuestActivityCard> visible;
  final Map<String, double> activityIdToFill;
  final Map<String, ActivityPinState> activityIdToState;
  final Map<String, bool> activityIdToPingStatus;
  final Map<String, PinTier> activityIdToTier;

  const _PinRenderer({
    required this.visible,
    required this.activityIdToFill,
    required this.activityIdToState,
    required this.activityIdToPingStatus,
    required this.activityIdToTier,
  });

  List<QuestActivityCard> get largeCards => visible
      .where((c) => c.point != null && tierOf(c.activityId) == PinTier.large)
      .toList();

  List<QuestActivityCard> get nonLargeCards => visible
      .where((c) => c.point != null && tierOf(c.activityId) != PinTier.large)
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

/// The stateless render of the persistent world map, driven by its
/// [WorldMapController]. It reads the controller's cached signals / stars /
/// pins / progression, applies the per-frame single-score relevance ranking to
/// pick each pin's tier (small dot / mid pin / large featured card), and lays
/// the pins, clusters, basemap tiles, and (World only) the search-filter overlay
/// over the map. All interaction routes back to the controller (tap a pin →
/// promote, tap a card → open the activity, filter → reload). No pin is ever
/// locked (#7186). See world-map.instructions.md.
class WorldMapView extends StatelessWidget {
  final WorldMapController controller;

  const WorldMapView(this.controller, {super.key});

  /// Resolve the per-frame pin draw model: the visible set, and for each pin its
  /// tier / colour-state / pinged / fill, plus the cluster dominant-state lookup.
  /// Applies the single-score relevance ranking that assigns tiers (a static
  /// top-N large set + a mid set), rebuilt each frame from the controller's
  /// cached signals + progression so a star award re-ranks next build. See
  /// world-map.instructions.md.
  _PinRenderer _resolvePinRender(BuildContext context) {
    final visible = controller.visiblePins;
    // No lock layering: the controller's signals pass through unchanged — nothing
    // is ever locked now, progression only ranks (#7186).
    final signals = controller.signals;
    final ranking = _getRankings(visible: visible, signals: signals);

    // The static large set (top of the score, no rotation) is auto-featured only
    // where there is horizontal room (desktop / column mode); a tap-promoted pin
    // renders large at any width.
    final desktop = FluffyThemes.isColumnMode(context);
    final largeIds = desktop ? ranking.largeIds.toSet() : <String>{};

    return _createPinRenderer(
      visible: visible,
      signals: signals,
      largeIds: largeIds,
      mediumIds: ranking.midIds,
    );
  }

  RankingResult _getRankings({
    required List<QuestActivityCard> visible,
    required Map<String, PinSignals> signals,
  }) {
    // Rank only the in-view pins (camera bounds when available) so promotion
    // reflects what the learner is looking at.
    List<QuestActivityCard> inView = visible;
    try {
      final bounds = controller.mapController.camera.visibleBounds;
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
      progression: controller.progression,
      signals: signals,
    );
  }

  _PinRenderer _createPinRenderer({
    required List<QuestActivityCard> visible,
    required Map<String, PinSignals> signals,
    required Set<String> largeIds,
    required Set<String> mediumIds,
  }) {
    final activityIds = visible.map((c) => c.activityId).toSet();

    final Map<String, PinTier> tiers = {};
    final Map<String, ActivityPinState> states = {};
    final Map<String, bool> pings = {};
    final Map<String, double> fills = {};

    for (final id in activityIds) {
      // A tap-promoted pin is large at any width; otherwise the static large set
      // (desktop only) is large, the mid set is mid, the rest are small.
      tiers[id] = id == controller.promotedActivityId || largeIds.contains(id)
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
    );
  }

  /// The clustered small/mid pins (large cards render unclustered above). Skips
  /// pins with no point and any promoted-to-large pin.
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
            card: card,
            state: state,
            tier: tier,
            onTap: () => controller.promoteToLarge(card),
            pinged: render.pingedOf(card.activityId),
            fill: render.fillOf(card.activityId),
          ),
        );
      }).toList();

  /// The 1–3 large featured cards (desktop) plus any tap-promoted card, rendered
  /// unclustered so they're always visible.
  List<Marker> _largeMarkers(_PinRenderer render) => render.largeCards.map((
    card,
  ) {
    // Hydrate the full plan for this featured card (no-op once cached); the
    // repo listener rebuilds the map when it lands.
    ActivityPlanRepo.instance.ensure(card.activityId);
    final plan = ActivityPlanRepo.instance.cachedPlan(card.activityId);

    final joinableActivity = controller.client?.bestJoinableActivityInstance(
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
          starsEarned: controller.userStars[card.activityId] ?? 0,
          participants: joinableActivity?.largeCardParticipants ?? [],
          openSlots: joinableActivity?.numRemainingRoles ?? 0,
          onTap: () => controller.openActivity(card),
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
    final clusterStateByPoint = render.clusterStateByPoint;

    final map = FlutterMap(
      mapController: controller.mapController,
      options: MapOptions(
        // The persistent instance keeps its own camera across navigation,
        // so no external camera-state restore is needed.
        initialCenter: controller.widget.initialCenter ?? const LatLng(20, 0),
        initialZoom: controller.widget.initialZoom ?? 3,
        // minZoom 3 (not 2): containLatitude rejects a move when the
        // constrained latitude band is shorter than the viewport, and the
        // ±90 band is only ~1024px tall at z2 — that would freeze *all*
        // panning on windows taller than ~1024px (common when maximized).
        // z3 gives a ~2048px band, clearing any realistic viewport.
        minZoom: WorldMapController.minZoom,
        maxZoom: WorldMapController.maxZoom,
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
          if (controller.promotedActivityId != null) controller.collapse();
        },
        // World pins are viewport-bounded: load once the camera is ready, then
        // re-load (debounced) as the user pans/zooms. Course pins are
        // context-bound and unaffected.
        onMapReady: () {
          if (controller.isWorld) controller.loadWorldPins();
        },
        onPositionChanged: (_, _) => controller.handleMapPositionChanged(),
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
            // else (#7072). Per the world-map design ("tap promotes, tap again
            // opens"), promote the tapped pin to its large card in place; a group
            // bubble still zooms to de-cluster (`zoomToBoundsOnClick`). The pin
            // carries its activity id as its key. Promote in place, no recenter.
            centerMarkerOnClick: false,
            onMarkerTap: (marker) {
              final key = marker.key;
              if (key is ValueKey<String>) {
                controller.promoteToLargeById(key.value);
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
              return Semantics(
                button: true,
                label: '${markers.length} ${L10n.of(context).activities}',
                excludeSemantics: true,
                child: WorldMapClusterBubble(
                  count: markers.length,
                  dominant: dominant,
                ),
              );
            },
          ),
        ),
        // Large cards (unclustered, always visible): the 1–3 auto-featured cards
        // on desktop plus any pin promoted by a tap.
        MarkerLayer(markers: _largeMarkers(render)),
        RichAttributionWidget(
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
      child: _MapZoomControls(controller: controller),
    );

    // A course shows its plain map (plus the controls); the world map adds the
    // search + filter overlay.
    if (!controller.isWorld) {
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
          left: controller.widget.leftOverlayWidth + 12,
          width: 360,
          child: WorldMapSearchOverlay(
            query: controller.query,
            onQueryChanged: controller.setQuery,
            l2Only: controller.l2Only,
            l2Label: l2?.toUpperCase(),
            onToggleL2: controller.toggleL2,
            onWidenSearch: () => controller.resetFilters(l2Only: false),
            selectedCefr: controller.cefrFilter,
            onToggleCefr: controller.toggleCefr,
            selectedCompletion: controller.completionFilter,
            onToggleCompletion: controller.toggleCompletion,
            results: render.visible,
            onResultTap: controller.flyTo,
            canReset: controller.canReset,
            onReset: controller.resetFilters,
            emptyInView: !controller.loadingPins && render.visible.isEmpty,
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
          final canZoomIn = zoom == null || WorldMapController.canZoomIn(zoom);
          final canZoomOut =
              zoom == null || WorldMapController.canZoomOut(zoom);
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
