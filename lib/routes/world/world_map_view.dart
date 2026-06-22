import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
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

/// The stateless render of the persistent world map, driven by its
/// [WorldMapController]. It reads the controller's cached signals / stars /
/// pins, applies the per-frame progression gate + relevance ranking to pick each
/// pin's tier (small dot / mid pin / large featured card), and lays the pins,
/// clusters, basemap tiles, and (World only) the search-filter overlay over the
/// map. All interaction routes back to the controller (tap a pin → promote, tap
/// a card → open the activity, filter → reload). See world-map.instructions.md.
class WorldMapView extends StatelessWidget {
  final WorldMapController controller;

  const WorldMapView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    // world-map-tiles Phase 1: free hosted tiles switched by app theme —
    // OpenStreetMap (light) / CartoDB Dark Matter (dark).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final retina = dark && MediaQuery.devicePixelRatioOf(context) > 1.0;

    // The pins actually shown: the loaded set narrowed by the active
    // search/filters (World only; a course shows its set as-is).
    final visible = controller.visiblePins;

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
      outlines: controller.objectiveCache.outlines,
      starsByActivity: controller.userStars,
    );
    final signals = <String, PinSignals>{};
    for (final card in visible) {
      final base = controller.signals[card.activityId] ?? const PinSignals();
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
      final bounds = controller.mapController.camera.visibleBounds;
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
      joinedObjectiveIds: controller.objectiveCache.ids,
      signals: signals,
    );
    // Record the pool size so the controller's rotation timer knows whether
    // there are more featured candidates than the budget (and should rotate).
    controller.largePoolSize = ranking.largePool.length;
    // The large featured cards (desktop only): a rotating window over the
    // joinable pool; pool members not currently featured render at mid weight.
    final largeWindow = <String>{};
    if (desktop && ranking.largePool.isNotEmpty) {
      final n = min(WorldMapController.largeBudget, ranking.largePool.length);
      for (var i = 0; i < n; i++) {
        largeWindow.add(
          ranking.largePool[(controller.largeRotationIndex + i) %
              ranking.largePool.length],
        );
      }
    }
    PinTier tierOf(String id) {
      // A tapped small/mid pin is promoted to its large card in place.
      if (id == controller.promotedActivityId) return PinTier.large;
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
    if (!controller.isWorld) return map;
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
            selectedCefr: controller.cefrFilter,
            onToggleCefr: controller.toggleCefr,
            selectedCompletion: controller.completionFilter,
            onToggleCompletion: controller.toggleCompletion,
            results: visible,
            onResultTap: controller.flyTo,
            canReset: controller.canReset,
            onReset: controller.resetFilters,
            emptyInView: !controller.loadingPins && visible.isEmpty,
          ),
        ),
      ],
    );
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
            onTap: () => controller.promoteToLarge(card),
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
            onTap: () => controller.promoteToLarge(card),
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
    final client = controller.client;
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
          starsEarned: controller.userStars[card.activityId] ?? 0,
          participants: info.participants,
          openSlots: info.openSlots,
          onTap: () => controller.openActivity(card),
        ),
      ),
    );
  }
}
