import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_constants.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The per-frame pin draw model resolved by [_WorldMapViewState._resolvePinRender]:
/// the visible set and, for each *rendered* pin id, its tier / colour-state /
/// pinged-badge / progress-fill. Only the pins the width-driven budget admits (the
/// top-`N` by score, plus the reserved trail) get a tier here; the rest are not
/// drawn (no clustering — world-map.instructions.md). Lets the build method read
/// as composition (resolve the model, then lay out the marker layers).
class _PinRenderer {
  final List<QuestActivityCard> visible;
  final Map<String, double> activityIdToFill;
  final Map<String, ActivityPinState> activityIdToState;
  final Map<String, bool> activityIdToPingStatus;

  /// Tier per rendered pin. A pin with no entry here fell outside the budget cap
  /// `N` this view and is not drawn (there is no cluster bubble to collapse into).
  final Map<String, PinTier> activityIdToTier;

  /// The id of the focused activity (its detail panel is open), or null. The
  /// pin/card carrying this id draws a distinct focus ring at whatever tier it
  /// sits — persistent through zoom/pan, cleared when the panel closes or
  /// another activity is focused (#7349). See world-map.instructions.md.
  final String? focusedId;

  const _PinRenderer({
    required this.visible,
    required this.activityIdToFill,
    required this.activityIdToState,
    required this.activityIdToPingStatus,
    required this.activityIdToTier,
    required this.focusedId,
  });

  List<QuestActivityCard> get largeCards => visible
      .where(
        (c) =>
            c.point != null && activityIdToTier[c.activityId] == PinTier.large,
      )
      .toList();

  /// The rendered mid + small pins (large cards render above). A pin with no tier
  /// assignment (beyond the budget cap `N`) is excluded — it is simply not drawn.
  List<QuestActivityCard> get nonLargeCards => visible.where((c) {
    if (c.point == null) return false;
    final tier = activityIdToTier[c.activityId];
    return tier == PinTier.mid || tier == PinTier.small;
  }).toList();

  // The progress fill is the activity's completion fraction, used to size the
  // inProgress gold star (world-map.instructions.md, "Goal Progress").
  double fillOf(String id) => activityIdToFill[id] ?? 0;

  ActivityPinState stateOf(String id) =>
      activityIdToState[id] ?? ActivityPinState.available;

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
/// It reads the controller's cached signals / stars / pins / progression, applies
/// the per-frame single-score relevance ranking capped by the width-driven pin
/// budget to pick each pin's tier (small dot / mid pin / large featured card),
/// and lays the pins, basemap tiles, and (World only) the search-filter overlay
/// over the map. Small dots render individually — no clustering. All interaction
/// routes back to the controller (tap any pin → open/focus the activity, filter →
/// reload). No pin is ever locked (#7186). See world-map.instructions.md.
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

  /// The marker box for a pin: the tier size, except an inProgress pin renders a
  /// gold star that can exceed a tiny dot's box, so its box is sized to hold the
  /// largest star ([PinSize.progressStarMax]).
  static Size _markerBox(ActivityPinState state, PinTier tier) =>
      state == ActivityPinState.inProgress
      ? const Size(PinSize.progressStarMax, PinSize.progressStarMax)
      : Size(tier.dotWidth, tier.dotHeight(state));

  /// Detects newly-gone non-large pins and adds them to [_exiting] using their
  /// last-known render state. Pins promoted to large are excluded (still
  /// visible as a card). Called at the top of [build] before the marker layers
  /// are constructed — mutates tracking maps without calling setState.
  void _updateExiting(_PinRenderer render) {
    final currentNonLargeIds = {
      for (final c in render.nonLargeCards) c.activityId,
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

  /// Resolve the per-frame pin draw model: the width-driven budget, the ranked +
  /// trail-reserved candidate list capped to `N`, and each rendered pin's tier /
  /// colour-state / pinged / fill. Rebuilt each frame from the controller's cached
  /// signals + progression so a star award or a panel opening re-ranks next build.
  /// See world-map.instructions.md ("Priority matrix").
  _PinRenderer _resolvePinRender(BuildContext context) {
    final visible = widget.controller.visiblePins;
    // No lock layering: the controller's signals pass through unchanged — nothing
    // is ever locked now, progression only ranks (#7186).
    final signals = widget.controller.signals;

    // The available visible-map width (viewport minus open panels) picks the
    // budget row: a total cap `N` split into large/mid/small caps + a trail
    // reservation (world-map.instructions.md, "Pin display").
    final budget = budgetForWidth(
      widget.controller.widget.availableVisibleMapWidth,
    );
    final ranking = _getRankings(
      visible: visible,
      signals: signals,
      budget: budget,
    );

    // Large cards exist only where the width affords them (budget.large > 0). The
    // placement pass fits the candidates' footprints to the screen (no overlap, no
    // edge spill, not under a panel), focused-first — see world-map.instructions.md
    // (pipeline step 4). When the large cap is zero the pass yields nothing.
    final placement = _placeLarge(
      visible: visible,
      candidates: ranking.ordered,
      largeBudget: budget.large,
      heavyEligibleIds: ranking.heavyEligibleIds,
    );

    // Split the ordered list by the caps: large = what placement fit, then mid,
    // then small takes the remainder of the N-capped list (so an unfilled large
    // slot flows down to lighter tiers rather than crowding).
    final largeIds = placement.largeIds.toSet();
    final rest = ranking.ordered.where((id) => !largeIds.contains(id)).toList();
    // Under the live-session gate, only live sessions are eligible for mid; every
    // other pin drops to small (world-map.instructions.md, the heavy-tier gate).
    final heavy = ranking.heavyEligibleIds;
    final mediumIds = rest
        .where((id) => heavy == null || heavy.contains(id))
        .take(budget.mid)
        .toSet();
    final smallIds = rest.where((id) => !mediumIds.contains(id)).toSet();

    return _createPinRenderer(
      visible: visible,
      signals: signals,
      largeIds: largeIds,
      mediumIds: mediumIds,
      smallIds: smallIds,
      focusedId: widget.controller.focusedActivityId,
    );
  }

  /// Footprint-aware placement of the large cards (pipeline step 4): projects each
  /// candidate to the screen via the live camera and keeps only those whose card
  /// fits the visible safe area (viewport minus the left/right overlays) without
  /// overlapping one already placed; the focused card is placed first. Falls back
  /// to the static top-N (focused first) on the rare frame where the camera isn't
  /// laid out yet. Yields nothing when [largeBudget] is zero (narrow width).
  PlacementResult _placeLarge({
    required List<QuestActivityCard> visible,
    required List<String> candidates,
    required int largeBudget,
    required Set<String>? heavyEligibleIds,
  }) {
    final focusedId = widget.controller.focusedActivityId;
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
        focusedId: focusedId,
        screenOffsetOf: (id) {
          final p = pointById[id];
          return p == null ? null : camera.latLngToScreenOffset(p);
        },
        cardSize: Size(
          PinTier.large.dotWidth,
          PinTier.large.dotHeight(ActivityPinState.joinable),
        ),
        safeArea: safeArea,
        largeBudget: largeBudget,
        heavyEligibleIds: heavyEligibleIds,
      );
    } catch (_) {
      // Camera not laid out yet: static top-N (focused first), no fit test.
      // The next (camera-ready) frame does the real placement. Still honours the
      // live-session gate — only live sessions are large-eligible.
      final eligible = heavyEligibleIds == null
          ? candidates
          : candidates.where(heavyEligibleIds.contains).toList();
      return PlacementResult(
        largeIds: <String>[
          if (focusedId != null && eligible.contains(focusedId)) focusedId,
          ...eligible.where((id) => id != focusedId),
        ].take(largeBudget).toList(),
      );
    }
  }

  RankingResult _getRankings({
    required List<QuestActivityCard> visible,
    required Map<String, PinSignals> signals,
    required PinBudget budget,
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
      largeBudget: budget.large,
      midBudget: budget.mid,
      smallBudget: budget.small,
      trailBudget: budget.trail,
      progressedIds: widget.controller.progressedActivityIds,
      isNewLearner: widget.controller.isNewLearner,
    );
  }

  _PinRenderer _createPinRenderer({
    required List<QuestActivityCard> visible,
    required Map<String, PinSignals> signals,
    required Set<String> largeIds,
    required Set<String> mediumIds,
    required Set<String> smallIds,
    required String? focusedId,
  }) {
    final Map<String, PinTier> tiers = {};
    for (final id in largeIds) {
      tiers[id] = PinTier.large;
    }
    for (final id in mediumIds) {
      tiers[id] = PinTier.mid;
    }
    for (final id in smallIds) {
      tiers[id] = PinTier.small;
    }

    final Map<String, ActivityPinState> states = {};
    final Map<String, bool> pings = {};
    final Map<String, double> fills = {};

    for (final c in visible) {
      final id = c.activityId;
      if (!tiers.containsKey(id)) continue; // beyond the cap N — not drawn

      final signal = signals[id];
      pings[id] = signal?.pinged ?? false;

      final sessionState = signal?.state;
      if (sessionState != null) {
        // A live-session state (joinable/joined) wins the colour.
        states[id] = sessionState;
        fills[id] = signal!.completionFraction;
      } else if ((widget.controller.activityStarsEarned(id) ?? 0) > 0) {
        // No live session, but the learner has stars → inProgress (the gold
        // trail star). No live signal carries the fraction here, so size the
        // star by completion: full when done, mid when partially progressed
        // (world-map.instructions.md, "Goal Progress").
        states[id] = ActivityPinState.inProgress;
        fills[id] = widget.controller.isActivityCompleted(id) ? 1.0 : 0.5;
      } else {
        states[id] = ActivityPinState.available;
        fills[id] = 0;
      }
    }

    return _PinRenderer(
      visible: visible,
      activityIdToFill: fills,
      activityIdToPingStatus: pings,
      activityIdToState: states,
      activityIdToTier: tiers,
      focusedId: focusedId,
    );
  }

  /// The rendered small/mid pins, each an individual marker (no clustering).
  /// Tapping any pin opens/focuses the activity in one step (no tap-to-peek).
  List<Marker> _dotMarkers(_PinRenderer render) =>
      render.nonLargeCards.map((card) {
        final state = render.stateOf(card.activityId);
        final tier = render.tierOf(card.activityId);
        final box = _markerBox(state, tier);

        return Marker(
          key: ValueKey(card.activityId),
          point: card.point!,
          width: box.width,
          height: box.height,
          child: WorldMapDot(
            key: ValueKey(card.activityId),
            card: card,
            state: state,
            tier: tier,
            onTap: () => widget.controller.openActivity(card),
            pinged: render.pingedOf(card.activityId),
            fill: render.fillOf(card.activityId),
            isFocused: card.activityId == render.focusedId,
          ),
        );
      }).toList();

  /// Dying pins rendered in a separate layer so they animate out without
  /// disturbing the live pins while shrinking.
  List<Marker> _exitingMarkers() =>
      _exiting.values.where((p) => p.card.point != null).map((p) {
        final box = _markerBox(p.state, p.tier);
        return Marker(
          key: ValueKey('exiting_${p.card.activityId}'),
          point: p.card.point!,
          width: box.width,
          height: box.height,
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
        );
      }).toList();

  /// The large featured cards the placement pass fit on screen, rendered
  /// unclustered so they're always visible.
  List<Marker> _largeMarkers(_PinRenderer render) => render.largeCards.map((
    card,
  ) {
    // Hydrate the full plan for this featured card (no-op once cached); the
    // repo listener rebuilds the map when it lands.
    ActivityPlanRepo.instance.ensure(card.activityId);
    final plan = ActivityPlanRepo.instance.cachedPlan(card.activityId);

    final joinableActivity = widget.controller.client
        ?.bestJoinableActivityInstance(card.activityId);

    final state = render.stateOf(card.activityId);
    final tier = PinTier.large;

    return Marker(
      point: card.point!,
      width: tier.dotWidth,
      // The inner Align lets the card hug its own content (each state is a
      // different height: available has no action row, inProgress-at-full adds
      // one, joinable adds the avatar row). Height here is only a ceiling so the
      // tallest variant isn't clipped; shorter cards don't stretch to fill it.
      // The extra tailHeight reserves room beneath the card for the pin tail.
      height: tier.dotHeight(state) + WorldMapLargeCard.tailHeight,
      alignment: Alignment.topCenter,
      child: Align(
        // Bottom-align so the card+tail hugs its pin (the tail tip lands on the
        // dot) instead of floating with a gap above it (#7153).
        alignment: Alignment.bottomCenter,
        child: WorldMapLargeCard(
          card: card,
          state: state,
          pinged: render.pingedOf(card.activityId),
          plan: plan,
          starsEarned:
              widget.controller.activityStarsEarned(card.activityId) ?? 0,
          participants: joinableActivity?.largeCardParticipants ?? [],
          openSlots: joinableActivity?.numRemainingRoles ?? 0,
          isFocused: card.activityId == render.focusedId,
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

    final map = Semantics(
      label: L10n.of(context).activities,
      container: true,
      child: FlutterMap(
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
          // Tapping empty map does not clear focus — a focus is cleared only by
          // closing its panel or focusing another (world-map.instructions.md).
          // World pins are viewport-bounded: load once the camera is ready, then
          // re-load (debounced) as the user pans/zooms. Course pins are
          // context-bound and unaffected.
          onMapReady: widget.controller.loadWorldPins,
          onPositionChanged: (_, hasGesture) =>
              widget.controller.onMapPositionChanged(hasGesture),
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
          // world_v2: activity pins by relevance tier + state, capped by the
          // width-driven budget. Small/mid dots render individually (no
          // clustering); the large featured cards render unclustered above so
          // they're always visible.
          MarkerLayer(markers: _dotMarkers(render)),
          // Dying pins (a separate layer) so they don't disturb the live pins
          // while animating out.
          MarkerLayer(markers: _exitingMarkers()),
          // Large cards (always visible): the featured cards the width affords.
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
      ),
    );

    // The on-map zoom-out / World control (#7086): pins and search only zoom the
    // camera IN, so this is the way back out. Pinned to the viewport bottom-right
    // and kept there when a right panel opens (#7166): the 88px cluster gutter
    // reserved beside the right column leaves room, so the controls no longer
    // slide left with the panel. (rightOverlayWidth still pads the camera fit in
    // world_map.dart so focal content lands in the uncovered area; only this
    // on-map chrome stays fixed.) Shown on world and course maps.
    final controls = Positioned(
      right: 12,
      bottom: 28,
      child: _MapZoomControls(controller: widget.controller),
    );

    // A course shows its plain map (plus the controls); the world map adds the
    // search + filter overlay.
    if (!widget.controller.isWorld) {
      return Semantics(
        label: L10n.of(context).activityMapLabel,
        container: true,
        child: Stack(
          children: [
            Positioned.fill(child: map),
            controls,
          ],
        ),
      );
    }
    final l2 = MatrixState.pangeaController.userController.userL2Code;
    return Semantics(
      label: L10n.of(context).activityMapLabel,
      container: true,
      child: Stack(
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
              onWidenSearch: () =>
                  widget.controller.resetFilters(l2Only: false),
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
      ),
    );
  }
}

/// The on-map zoom controls (#7086): a small bottom-right stack with a World
/// reset (the one obvious "zoom out to everything", since pins/search only ever
/// zoom the camera IN) and +/- zoom steps. Camera-only — it never changes the
/// open panels or the course scope.
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
          return Semantics(
            label: l10n.mapZoomLabel,
            container: true,
            child: Column(
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
            ),
          );
        },
      ),
    );
  }
}
