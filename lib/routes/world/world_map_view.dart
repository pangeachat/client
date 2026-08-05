import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/activity_participant_row.dart';
import 'package:fluffychat/routes/world/dot_markers_layer.dart';
import 'package:fluffychat/routes/world/exiting_large_markers_layer.dart';
import 'package:fluffychat/routes/world/exiting_markers_layer.dart';
import 'package:fluffychat/routes/world/large_markers_layer.dart';
import 'package:fluffychat/routes/world/map_exit_tracker.dart';
import 'package:fluffychat/routes/world/mid_size_pin_labels_layer.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_constants.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/layouts/panel_allocator.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The per-frame pin draw model resolved by [_WorldMapViewState._resolvePinRender]:
/// the visible set and, for each *rendered* pin id, its tier / colour-state /
/// pinged-badge / star tier. Only the pins the width-driven budget admits (the
/// top-`N` by score, plus the reserved trail) get a tier here; the rest are not
/// drawn (no clustering — world-map.instructions.md). Lets the build method read
/// as composition (resolve the model, then lay out the marker layers).
class _PinRenderer {
  final List<QuestActivityCard> visible;
  final Map<String, ActivityStarLevel> activityIdToStarLevel;
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

  /// Which mid pins show an activity-name side-label and on which side, from
  /// the [placePinLabels] geometry pass (world-map.instructions.md, "Pin
  /// display"). Frozen with the rest of the model while the camera moves.
  final LabelPlacementResult labels;

  /// The measured pixel [Size] of each labelled mid pin's label (matches
  /// [kPinLabelTextStyle]), so [_labelMarkers] reuses it instead of
  /// re-measuring.
  final Map<String, Size> labelSizes;

  /// Ids of `available` pins the learner can't start yet — their role count
  /// exceeds the course's available members (course-scoped map only). These
  /// pins and their labels render at half opacity. Never holds joinable /
  /// ongoing / inProgress ids, and is empty on the world map.
  final Set<String> nonStartableIds;

  const _PinRenderer({
    required this.visible,
    required this.activityIdToStarLevel,
    required this.activityIdToState,
    required this.activityIdToPingStatus,
    required this.activityIdToTier,
    required this.focusedId,
    this.labels = const LabelPlacementResult(),
    this.labelSizes = const {},
    this.nonStartableIds = const {},
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

  // The completion tier for the inProgress (trail) state — a plain star vs a
  // super star, or none (world-map.instructions.md, "Goal Progress").
  ActivityStarLevel starLevelOf(String id) =>
      activityIdToStarLevel[id] ?? ActivityStarLevel.none;

  ActivityPinState stateOf(String id) =>
      activityIdToState[id] ?? ActivityPinState.available;

  /// True when [id] is an `available` pin the learner can't start yet — its
  /// pin and label render at half opacity (course-scoped map only).
  bool nonStartableOf(String id) => nonStartableIds.contains(id);

  bool pingedOf(String id) => activityIdToPingStatus[id] ?? false;

  PinTier tierOf(String id) => activityIdToTier[id] ?? PinTier.small;
}

/// Cached render snapshot for a pin that is animating out of the active set.
class PinSnapshot {
  final QuestActivityCard card;
  final ActivityPinState state;
  final PinTier tier;
  final bool pinged;
  final ActivityStarLevel starLevel;

  const PinSnapshot({
    required this.card,
    required this.state,
    required this.tier,
    required this.pinged,
    required this.starLevel,
  });
}

/// Cached render snapshot for a large card that is animating out (demoted, or
/// simply no longer fits) — everything [WorldMapLargeCard] needs, frozen at
/// its last live frame so it renders identically while it shrinks away.
class LargeCardSnapshot {
  final QuestActivityCard card;
  final ActivityPinState state;
  final bool pinged;
  final ActivityPlanModel? plan;
  final Room? liveRoom;
  final int starsEarned;
  final List<LargeCardParticipant> participants;
  final int openSlots;
  final ActivityStarLevel starLevel;

  const LargeCardSnapshot({
    required this.card,
    required this.state,
    required this.pinged,
    required this.plan,
    required this.liveRoom,
    required this.starsEarned,
    required this.participants,
    required this.openSlots,
    required this.starLevel,
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
  /// Height of the narrow-mode bottom chrome (the floating nav rail + the
  /// search bar riding above it, with their gaps) that on-map overlays must
  /// clear (#7218). Update alongside the chrome if its heights change.
  static const double _narrowBottomChromeInset = 140.0;

  /// Entry/exit animation bookkeeping for the small/mid dot tier: which pins
  /// are shrinking out, and which have already played their pop-in. See
  /// [MapExitTracker] for why only an on-screen pin ever animates out (#8155).
  final MapExitTracker<PinSnapshot> _dotExits = MapExitTracker();

  /// Mirrors [_dotExits] for the large tier ([WorldMapLargeCardAnimated]): a
  /// card demoted out of the tier (X-dismissed, out-ranked, or no longer fits)
  /// shrinks away instead of vanishing instantly, while its dot (mid where
  /// eligible, else small) pops in fresh the same frame.
  final MapExitTracker<LargeCardSnapshot> _largeExits = MapExitTracker();

  /// The last render model computed while the camera was settled. Reused
  /// as-is while [WorldMapController.isActivelyMoving] is true, instead of
  /// recomputing tiers/placement against the live, still-moving camera —
  /// every pin/card holds its tier and size through a pan/zoom gesture and
  /// only actually resizes/dismisses once movement is confirmed settled
  /// (#7245).
  _PinRenderer? _lastSettledRenderer;

  /// The marker box for a pin: the tier size, except an inProgress pin renders a
  /// gold star that can exceed a tiny dot's box, so its box is sized to hold the
  /// largest star (the super star, [PinSize.superStarDotDiameter]).
  static Size _markerBox(ActivityPinState state, PinTier tier) =>
      state == ActivityPinState.inProgress
      ? const Size(PinSize.superStarDotDiameter, PinSize.superStarDotDiameter)
      : Size(tier.dotWidth, tier.dotHeight(state));

  /// The marker's anchor within its box — where [Marker.point] (the geographic
  /// coordinate) lands on screen. A mid pin is a teardrop whose pointed tip is
  /// the true location marker, so the anchor must sit at that tip (the bottom-
  /// centre of the box — the count now stacks inside the head, so there's no
  /// reserved label row and the tip is the box's lowest point), not the box's
  /// vertical centre (flutter_map's default `Alignment.center`) — otherwise the
  /// pin would float off its true location.
  ///
  /// flutter_map's `alignment` is inverted from intuition — `Alignment.topCenter`
  /// puts the marker *above* the point (so the point lands at the box's bottom).
  /// [Marker.computePixelAlignment] does that sign for us from the tip's pixel
  /// offset down the box, so this stays correct even if a label row below the
  /// tip is ever reintroduced. Every other case (small dot, inProgress star) is
  /// a plain box with no point, so the default centre anchor is already correct.
  static Alignment _markerAlignment(ActivityPinState state, PinTier tier) {
    if (tier != PinTier.mid || state == ActivityPinState.inProgress) {
      return Alignment.center;
    }
    final tipY = PinSize.midDiameter + PinSize.midPointHeight;
    final boxHeight = tipY + PinSize.midLabelHeight;
    return Marker.computePixelAlignment(
      width: PinSize.midDiameter,
      height: boxHeight,
      left: PinSize.midDiameter / 2,
      top: tipY,
    );
  }

  /// Measure a mid-pin label at [kPinLabelTextStyle] (honouring the platform
  /// text scaler) so the placement pass and the marker box use the painted
  /// size. Capped at [kPinLabelMaxWidth]; [kPinLabelHaloPad] leaves room for the
  /// white halo stroke so it isn't clipped and collisions include it.
  Size _measureLabel(BuildContext context, String title) {
    final tp = TextPainter(
      text: TextSpan(text: title, style: kPinLabelTextStyle),
      maxLines: 1,
      ellipsis: '…',
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: kPinLabelMaxWidth);
    final size = Size(
      tp.width + 2 * kPinLabelHaloPad,
      tp.height + 2 * kPinLabelHaloPad,
    );
    tp.dispose();
    return size;
  }

  /// Choose each labelable mid pin's side via the live camera projection,
  /// mirroring [_placeLarge]: same safe area (viewport minus the side overlays),
  /// with the placed large cards as obstacles so a label never lands on a card.
  /// Falls back to no labels on the rare frame the camera isn't laid out yet.
  LabelPlacementResult _placeLabels({
    required List<String> orderedIds,
    required Map<String, QuestActivityCard> cardById,
    required Map<String, Size> labelSizes,
    required Set<String> largeIds,
  }) {
    if (orderedIds.isEmpty) return const LabelPlacementResult();
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
      Offset? offsetOf(String id) {
        final p = cardById[id]?.point;
        return p == null ? null : camera.latLngToScreenOffset(p);
      }

      // Placed large cards sit above labels, so treat their footprints as
      // obstacles — a label never paints under a card. The card box is anchored
      // bottom-centre on the pin (topCenter marker), matching placeLargeCards.
      final cardSize = Size(
        PinTier.large.dotWidth,
        PinTier.large.dotHeight(ActivityPinState.joinable),
      );
      final obstacles = <Rect>[
        for (final id in largeIds)
          if (offsetOf(id) case final o?)
            Rect.fromLTWH(
              o.dx - cardSize.width / 2,
              o.dy - cardSize.height,
              cardSize.width,
              cardSize.height,
            ),
      ];

      return placePinLabels(
        orderedIds: orderedIds,
        screenOffsetOf: offsetOf,
        labelSizeOf: (id) => labelSizes[id] ?? Size.zero,
        safeArea: safeArea,
        obstacleRects: obstacles,
        previousSides: _lastSettledRenderer?.labels.sides ?? const {},
      );
    } catch (_) {
      return const LabelPlacementResult();
    }
  }

  /// Whether [point] currently falls inside the camera's visible bounds — the
  /// gate on queueing (and keeping) an exit animation, since flutter_map's
  /// MarkerLayer only builds markers it doesn't cull. Null point, or a camera
  /// that isn't laid out yet, counts as on screen so nothing is dropped before
  /// the map can answer.
  bool _isOnScreen(LatLng? point) {
    if (point == null) return true;
    try {
      return widget.controller.mapController.camera.visibleBounds.contains(
        point,
      );
    } catch (_) {
      return true;
    }
  }

  /// Hands this frame's non-large pins to [_dotExits], which detects the ones
  /// newly gone and starts their shrink-out from their last-known render state
  /// — **including** a pin promoted to large: its dot shrinks away in this layer
  /// while [WorldMapLargeCardAnimated] grows the new card in at the same spot
  /// ([_largeMarkers]), so promotion reads as one pin morphing into a card
  /// rather than an instant swap. A pin the camera merely panned away from is
  /// dropped instead of animated (#8155 — see [MapExitTracker]). Called at the
  /// top of [build] before the marker layers are constructed — mutates the
  /// trackers without calling setState.
  void _updateExiting(_PinRenderer render) {
    _dotExits.update(
      active: {
        for (final card in render.nonLargeCards)
          card.activityId: PinSnapshot(
            card: card,
            state: render.stateOf(card.activityId),
            tier: render.tierOf(card.activityId),
            pinged: render.pingedOf(card.activityId),
            starLevel: render.starLevelOf(card.activityId),
          ),
      },
      isOnScreen: (snapshot) => _isOnScreen(snapshot.card.point),
    );
  }

  /// Mirrors [_updateExiting] for the large tier, over the cards resolved for
  /// this frame.
  void _updateExitingLarge(Map<String, LargeCardSnapshot> currentLarge) {
    _largeExits.update(
      active: currentLarge,
      isOnScreen: (snapshot) => _isOnScreen(snapshot.card.point),
    );
  }

  /// Resolve the per-frame pin draw model: the width-driven budget, the ranked +
  /// trail-reserved candidate list capped to `N`, and each rendered pin's tier /
  /// colour-state / pinged / star tier. Rebuilt each frame from the controller's cached
  /// signals + progression so a star award or a panel opening re-ranks next build.
  /// See world-map.instructions.md ("Priority matrix").
  _PinRenderer _resolvePinRender(BuildContext context) {
    // While the camera is actively moving, hold the last-settled render model
    // instead of recomputing against the live, still-moving camera bounds —
    // freezes every pin/card's tier and size for the gesture's duration
    // (#7245). The same freeze also holds through the L1 shimmer window, so pins
    // keep their pre-change tiers instead of re-tiering against reset signals.
    // Falls through to a fresh compute if nothing has settled yet (e.g. the very
    // first frame).
    final cached = _lastSettledRenderer;
    if ((widget.controller.isActivelyMoving || widget.controller.warmingPins) &&
        cached != null) {
      return cached;
    }

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
    // This whole render model only runs while the camera is settled (the
    // isActivelyMoving guard above), so there is no live-gesture case to
    // special-case here any more (#7245).
    final placement = _placeLarge(
      visible: visible,
      candidates: ranking.ordered,
      largeBudget: budget.large,
      largeEligibleIds: ranking.largeEligibleIds,
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

    final render = _createPinRenderer(
      context: context,
      visible: visible,
      signals: signals,
      largeIds: largeIds,
      mediumIds: mediumIds,
      smallIds: smallIds,
      focusedId: widget.controller.focusedActivityId,
    );
    _lastSettledRenderer = render;
    return render;
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
    required Set<String> largeEligibleIds,
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
        largeEligibleIds: largeEligibleIds,
        dismissedIds: widget.controller.dismissedLargeIds,
      );
    } catch (_) {
      // Camera not laid out yet: static top-N (focused first), no fit test.
      // The next (camera-ready) frame does the real placement. Still honours the
      // large-tier hard gate — only joinable/ongoing pins are large-eligible —
      // and the X-dismissals (#7207), so a dismissed card cannot flash back for
      // a frame.
      final dismissed = widget.controller.dismissedLargeIds;
      final eligible = candidates
          .where((id) => !dismissed.contains(id))
          .where(largeEligibleIds.contains)
          .toList();
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
      // The multi-person "first map" deprioritize is a WORLD-map affordance:
      // in a course, the author chose those activities, so a 3+ person one
      // shouldn't be ranked down for a new learner. Gating to world also keeps
      // the pre-existing behavior now that course pins carry a real roleCount.
      isNewLearner: widget.controller.isNewLearner && widget.controller.isWorld,
      dismissedIds: widget.controller.dismissedLargeIds,
    );
  }

  _PinRenderer _createPinRenderer({
    required BuildContext context,
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
    final Map<String, ActivityStarLevel> starLevels = {};
    // `available` pins the course lacks the members to start (course-scoped
    // only; null on the world map or an unjoined course → nothing dims).
    final int? available = widget.controller.courseAvailableParticipants;
    final Set<String> nonStartableIds = {};
    for (final c in visible) {
      final id = c.activityId;
      if (!tiers.containsKey(id)) continue; // beyond the cap N — not drawn

      pings[id] = signals[id]?.pinged ?? false;

      // The learner's completion tier and the pin's resolved display state come
      // from the shared resolver in the pins manager (reuse), so the Status
      // filter and this renderer never drift: a live-session state wins the
      // colour, else the completed star tier layers in (the star rides behind a
      // live pin), else the plain `available` default. A gold star appears ONLY
      // once a full role is done — a plain star (≥1 role) or super star (all
      // roles); partial progress is never shown (world-map.instructions.md,
      // "Goal Progress" / "Pin state").
      starLevels[id] = widget.controller.starLevelOf(c);
      states[id] = widget.controller.displayStateOf(c);

      // Dim only plain `available` pins whose role count outruns the course's
      // members
      if (available != null &&
          states[id] == ActivityPinState.available &&
          (c.roleCount ?? 0) > available) {
        nonStartableIds.add(id);
      }
    }

    // Mid pins carry a Google-Maps-style activity-name label; small dots and
    // the gold-star (inProgress) state never do (world-map.instructions.md,
    // "Pin display"). Measure + place here so the labels freeze into the
    // settled snapshot alongside the tiers (the isActivelyMoving guard).
    final cardById = {for (final c in visible) c.activityId: c};
    final labelableIds = [
      for (final id in mediumIds)
        if (states[id] != null &&
            states[id] != ActivityPinState.inProgress &&
            cardById[id]?.point != null)
          id,
    ];
    final labelSizes = {
      for (final id in labelableIds)
        id: _measureLabel(context, cardById[id]!.title),
    };
    final labels = _placeLabels(
      orderedIds: labelableIds,
      cardById: cardById,
      labelSizes: labelSizes,
      largeIds: largeIds,
    );

    return _PinRenderer(
      visible: visible,
      activityIdToStarLevel: starLevels,
      activityIdToPingStatus: pings,
      activityIdToState: states,
      activityIdToTier: tiers,
      focusedId: focusedId,
      labels: labels,
      labelSizes: labelSizes,
      nonStartableIds: nonStartableIds,
    );
  }

  /// The session's featured participants + open-seat count for [activityId],
  /// sourced per [state]: a `joinable` session reads its local room-preview
  /// (or, for a discovered/invited session, its `room_preview` summary — #7488)
  /// row; `ongoingPending` reads the learner's own live room. Every lookup is
  /// state-guarded, so a state with no participant row (`ongoingActive`,
  /// `available`, `inProgress`) does no `client.rooms` scan and returns empty.
  /// The single source shared by the mid-pin "num/num" label
  /// ([_participantCounts]) and the large card's participant row
  /// ([_snapshotLargeCard]) so the two can never drift. When the caller already
  /// holds the learner's live room (the large card resolves it for the message
  /// preview too), it passes [liveRoom] so the `ongoingPending` arm reuses it
  /// instead of re-scanning.
  ({List<LargeCardParticipant> participants, int openSlots})
  _sessionParticipants(
    String activityId,
    ActivityPinState state, {
    Room? liveRoom,
  }) {
    switch (state) {
      case ActivityPinState.joinable:
        final joinableActivity = widget.controller.client
            ?.bestJoinableActivityInstance(activityId);
        final discoveredSummary = joinableActivity == null
            ? DiscoveredSessionsCache.instance.bestOpenSummary(activityId)
            : null;
        return (
          participants:
              joinableActivity?.largeCardParticipants ??
              discoveredSummary?.largeCardParticipants ??
              const <LargeCardParticipant>[],
          openSlots:
              joinableActivity?.numRemainingRoles ??
              discoveredSummary?.openSlots ??
              0,
        );
      case ActivityPinState.ongoingPending:
        final room =
            liveRoom ??
            widget.controller.client?.activeActivityInstance(activityId);
        return (
          participants:
              room?.largeCardParticipants ?? const <LargeCardParticipant>[],
          openSlots: room?.numRemainingRoles ?? 0,
        );
      default:
        return (participants: const <LargeCardParticipant>[], openSlots: 0);
    }
  }

  /// Resolves everything [WorldMapLargeCard] needs for [card] — hydrates the
  /// plan, and sources participants/seats from the right place per state (a
  /// joinable session's room-preview/room, or the learner's own live room for
  /// Ongoing). Shared by [_largeMarkers] (the live layer) and
  /// [_updateExitingLarge] (freezing a snapshot for the card's exit
  /// animation), so both read identical data.
  LargeCardSnapshot _snapshotLargeCard(
    QuestActivityCard card,
    _PinRenderer render,
  ) {
    // Hydrate the full plan for this featured card (no-op once cached); the
    // repo listener rebuilds the map when it lands.
    ActivityPlanRepo.instance.ensure(card.activityId);
    final plan = ActivityPlanRepo.instance.cachedPlan(card.activityId);

    final state = render.stateOf(card.activityId);

    // Ongoing (pending/active) cards need the learner's own session room:
    // pending reads its participant/seat row from it (same shape as joinable's
    // room-derived row), active reads its last chat event for the message
    // preview (world-map.instructions.md, "Pin state"). Resolved once here and
    // handed to [_sessionParticipants] so the pending row doesn't re-scan.
    final liveRoom = state.isOngoing
        ? widget.controller.client?.activeActivityInstance(card.activityId)
        : null;

    // Participants + open seats from the shared resolver (the joinable lookup
    // is state-guarded inside it, so an ongoing card no longer wastes a
    // room-preview scan it would discard).
    final (:participants, :openSlots) = _sessionParticipants(
      card.activityId,
      state,
      liveRoom: liveRoom,
    );

    return LargeCardSnapshot(
      card: card,
      state: state,
      pinged: render.pingedOf(card.activityId),
      plan: plan,
      liveRoom: liveRoom,
      // ongoingActive's star row is the CURRENT session's own progress, not
      // the all-time/cross-session max (world-map.instructions.md, "Goal
      // Progress") — every other state keeps the all-time value.
      starsEarned: state == ActivityPinState.ongoingActive
          ? (liveRoom?.ownCompletedGoals.length ?? 0)
          : (widget.controller.activityStarsEarned(card.activityId) ?? 0),
      participants: participants,
      openSlots: openSlots,
      // The completed-activity trail tier (all-time), so a live large card on a
      // previously-completed activity still shows its star below the caret.
      starLevel: render.starLevelOf(card.activityId),
    );
  }

  /// #7813: a resize can raise the viewport-derived zoom-out floor above the
  /// camera's current zoom (window grown, phone rotated). Left below the floor,
  /// containLatitude rejects every camera move and panning freezes — so nudge
  /// the camera up to the new floor once the frame settles. No-op when the
  /// camera already sits at or above the floor, or before the map is laid out
  /// (reading the camera throws until then; initial zoom is above any floor).
  void _reclampCameraIfBelow(double minZoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = widget.controller.mapController;
      try {
        if (ctrl.camera.zoom < minZoom) {
          ctrl.move(ctrl.camera.center, minZoom);
        }
      } catch (_) {}
    });
  }

  void _onExitedMarker(String activityId) {
    if (mounted) setState(() => _dotExits.finishExit(activityId));
  }

  void _onExitedLargeCardMarker(String activityId) {
    if (mounted) {
      setState(() => _largeExits.finishExit(activityId));
    }
  }

  @override
  Widget build(BuildContext context) {
    // world-map-tiles Phase 1: free hosted tiles switched by app theme —
    // OpenStreetMap (light) / CartoDB Dark Matter (dark).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final retina = dark && MediaQuery.devicePixelRatioOf(context) > 1.0;
    // What shows through wherever tiles have not arrived yet. Matched to each
    // basemap's own paper — CartoDB Dark Matter's near-black, OSM's pale beige
    // — so a gap during a zoom reads as unfilled map rather than the light
    // grey flash flutter_map defaults to (#7937).
    final mapBackground = dark
        ? const Color(0xFF0E0E0E)
        : const Color(0xFFF2EFE9);

    final warming = widget.controller.warmingPins;

    // Resolve which pins to draw and each one's tier/state/pinged/star-tier once
    // per frame, then lay out the layers from it.
    final render = _resolvePinRender(context);

    // Detect newly-gone pins before building the marker layers.
    _updateExiting(render);

    // Resolve every current large card's data once (shared by the live layer
    // and the exiting-large tracker) and detect newly-gone large cards.
    final currentLarge = {
      for (final c in render.largeCards)
        c.activityId: _snapshotLargeCard(c, render),
    };
    _updateExitingLarge(currentLarge);

    final map = Semantics(
      label: L10n.of(context).activities,
      container: true,
      // ExcludeSemantics (#8013): flutter_map taps the map through a plain
      // `GestureDetector` (PositionedTapDetector2) that never sets
      // `excludeFromSemantics`, so it publishes a tap action over the map's
      // whole hit area — the entire viewport. Flutter web renders a tappable
      // semantics node as `role=button` with `pointer-events: all`, so with the
      // semantics tree on (staging forces it via ENABLE_SEMANTICS; Flutter also
      // enables it for assistive tech) that one node blankets every DOM
      // platform view layered over the map — the activity plan's YouTube
      // `<iframe>`, an uploaded `<video>` — and swallows the mouse events those
      // embeds need, leaving their own controls dead.
      //
      // COST, accepted deliberately: this drops the pins' own
      // Semantics(button) nodes too, so map pins are not reachable by a screen
      // reader until the upstream fix lands. Narrower cuts were tried and do
      // NOT clear it (excluding just the attribution, unmerging this container)
      // — the offending node is flutter_map's own map-level tap detector.
      // Upstream fix filed against fleaflet/flutter_map; revert this to a
      // narrower scope once a released version carries it.
      child: ExcludeSemantics(
        // Any pointer-down on the map drops text-input focus, so tapping or
        // panning the map closes the search bar's keyboard — on a narrow screen
        // an open keyboard pins most of the viewport (#7635). Listener observes
        // without consuming, so pin taps and map gestures are unaffected. (Pin
        // FOCUS is separate and deliberately not cleared by map taps — see the
        // note on MapOptions below.)
        child: Listener(
          onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          // The scroll wheel is ours, not flutter_map's (#7937): its handler
          // moves the camera the instant each event lands, so a zoom arrives as
          // a burst of snaps. `scrollWheelZoom` is off in the flags below and
          // the controller eases each step instead. Registering with the
          // signal resolver (exactly as flutter_map's own handler does) keeps a
          // scrollable ancestor from acting on the same event.
          onPointerSignal: (signal) {
            if (signal is! PointerScrollEvent) return;
            if (signal.scrollDelta.dy == 0) return;
            GestureBinding.instance.pointerSignalResolver.register(signal, (
              resolved,
            ) {
              resolved as PointerScrollEvent;
              widget.controller.scrollZoomBy(
                resolved.scrollDelta.dy,
                resolved.localPosition,
              );
            });
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The zoom-out floor is viewport-derived (#7813): out to where one
              // world copy would become smaller than the map's height or width,
              // whichever binds first. The height term is also what keeps
              // containLatitude from rejecting every move (freezing all panning)
              // when the ±90 band is shorter than the viewport — the old fixed
              // floor of 3 guarded that for desktop but left phones unable to
              // pull back to the world. A resize can raise the floor above the
              // current zoom (window grown, rotation); re-clamp the camera then,
              // or panning freezes exactly as above.
              final minZoom = WorldMapConstants.minZoomFor(constraints.biggest);
              _reclampCameraIfBelow(minZoom);
              // Locals so _ShimmerLayer can wrap them without duplicating their
              // construction.
              final Widget dotLayer = DotMarkersLayer(
                nonLargeCards: render.nonLargeCards,
                stateOf: render.stateOf,
                nonStartableOf: render.nonStartableOf,
                tierOf: render.tierOf,
                starLevelOf: render.starLevelOf,
                pingedOf: render.pingedOf,
                activeActivityInstance:
                    widget.controller.client?.activeActivityInstance,
                markerBox: _markerBox,
                markerAlignment: _markerAlignment,
                sessionParticipants: (a, b) => _sessionParticipants(a, b),
                focusedId: render.focusedId,
                onTap: widget.controller.openActivity,
                // markEntered returns true only the first build a pin appears
                // — it animates in then, and holds full scale through the
                // State recreations MarkerLayer causes mid-gesture (#8136).
                animateInOf: _dotExits.markEntered,
              ).layer();
              final Widget largeLayer = LargeMarkersLayer(
                largeCards: render.largeCards,
                currentLarge: currentLarge,
                focusedId: render.focusedId,
                onTap: widget.controller.openActivity,
                onClose: widget.controller.dismissLargeCard,
                animateInOf: _largeExits.markEntered,
              ).layer();
              return FlutterMap(
                mapController: widget.controller.mapController,
                options: MapOptions(
                  // The persistent instance keeps its own camera across
                  // navigation, so no external camera-state restore is needed.
                  initialCenter:
                      widget.controller.widget.initialCenter ??
                      const LatLng(20, 0),
                  initialZoom: widget.controller.widget.initialZoom ?? 3,
                  minZoom: minZoom,
                  maxZoom: WorldMapConstants.maxZoom,
                  // Clamp latitude only — leaving longitude free so the user can pan
                  // east-west and the world wraps seamlessly ("rotate the world
                  // around"). Epsg3857 replicates longitude, so tiles and markers
                  // repeat across world copies automatically. A longitude-bounded
                  // `contain`/`containCenter` pins the camera when zoomed out and hides
                  // content behind the left column with no way to pan it out.
                  cameraConstraint: const CameraConstraint.containLatitude(
                    90,
                    -90,
                  ),
                  // Un-tiled map area — every gap a zoom opens up before its
                  // tiles arrive — paints this. flutter_map's default is a
                  // light grey (#E0E0E0), which is what makes a zoom
                  // "flashbang" a dark-theme user (#7937).
                  backgroundColor: mapBackground,
                  interactionOptions: const InteractionOptions(
                    // Scroll-wheel zoom is handled by the `Listener` above so
                    // it can be eased rather than snapped (#7937).
                    flags:
                        InteractiveFlag.all &
                        ~InteractiveFlag.rotate &
                        ~InteractiveFlag.scrollWheelZoom,
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
                  _ShimmerLayer(active: warming, child: dotLayer),
                  // Activity-name labels for mid pins, above the dots but below the
                  // large cards (world-map.instructions.md, "Pin display"; z-order:
                  // small < mid < labels < large).
                  MidSizePinLabelsLayer(
                    nonLargeCards: render.nonLargeCards,
                    sideOf: render.labels.sideOf,
                    sizeOf: (id) => render.labelSizes[id],
                    stateOf: render.stateOf,
                    nonStartableOf: render.nonStartableOf,
                    onTap: widget.controller.openActivity,
                  ).layer(),
                  // Dying pins (a separate layer) so they don't disturb the live pins
                  // while animating out.
                  ExitingMarkersLayer(
                    exiting: _dotExits.exiting,
                    markerBox: _markerBox,
                    markerAlignment: _markerAlignment,
                    onExited: _onExitedMarker,
                  ).layer(),
                  // Dying large cards (demoted, or bumped out) shrinking away beneath
                  // the live layer.
                  ExitingLargeMarkersLayer(
                    exitingLarge: _largeExits.exiting,
                    onExited: _onExitedLargeCardMarker,
                  ).layer(),
                  // Large cards (always visible): the featured cards the width affords.
                  _ShimmerLayer(active: warming, child: largeLayer),
                  Positioned(
                    // On a narrow screen the bottom chrome (nav widget + the search bar
                    // riding above it) owns the bottom edge, so lift the attribution
                    // above it — otherwise it sits unreadable UNDER the floating rail
                    // (#7218 on narrow).
                    left: 0,
                    bottom: FluffyThemes.isColumnMode(context)
                        ? 0.0
                        : _narrowBottomChromeInset,
                    child: SafeArea(
                      child: Stack(
                        children: [
                          // Background so attributions button
                          // is visible in dark mode
                          Positioned(
                            left: PlatformInfos.isMobile ? 12 : 8,
                            bottom: PlatformInfos.isMobile ? 12 : 8,
                            child: Container(
                              height: 32,
                              width: 32,
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(130, 135, 135, 135),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          RichAttributionWidget(
                            // #7218: bottom-LEFT so the attribution and its expand popup don't
                            // sit under the bottom-right zoom/World controls (where it was
                            // covered and hard to read, especially in dark mode).
                            alignment: AttributionAlignment.bottomLeft,
                            attributions: [
                              TextSourceAttribution(
                                'OpenStreetMap contributors',
                                onTap: () {},
                              ),
                              if (dark)
                                TextSourceAttribution('CARTO', onTap: () {}),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    // The on-map zoom-out / World control (#7086): pins and search only zoom the
    // camera IN, so this is the way back out. Pinned to the viewport bottom-right
    // and kept there when a right panel opens (#7166): the 88px cluster gutter
    // reserved beside the right column leaves room, so the controls no longer
    // slide left with the panel. (rightOverlayWidth still pads the camera fit in
    // world_map.dart so focal content lands in the uncovered area; only this
    // on-map chrome stays fixed.) Shown on world and course maps.
    // Column mode only: on a narrow screen the bottom chrome (the nav widget +
    // search bar) owns this corner, pinch handles zoom, and the rail's World
    // item is the reset — the Google Maps mobile pattern (no on-map +/- there).
    final Widget controls = FluffyThemes.isColumnMode(context)
        ? Positioned(
            right: 12,
            bottom: 28,
            child: _MapZoomControls(controller: widget.controller),
          )
        : const SizedBox.shrink();

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
    // The overlay lives in the EXPOSED map sliver: right of the open left
    // panels, clear of the right column / the top-right cluster gutter (a fixed
    // 360 slid under the cluster and off-screen whenever panels squeezed the
    // sliver — the surviving overlap in #7088). Below a usable width it hides
    // entirely; close a panel to search.
    final searchLeft = widget.controller.widget.leftOverlayWidth + 12;
    final searchWidth = math.min(
      360.0,
      MediaQuery.sizeOf(context).width -
          searchLeft -
          math.max(
            widget.controller.widget.rightOverlayWidth,
            PanelAllocator.clusterGutter,
          ) -
          12,
    );
    return Semantics(
      label: L10n.of(context).activityMapLabel,
      container: true,
      child: Stack(
        children: [
          Positioned.fill(child: map),
          // Column mode only: on a narrow screen the search rides the floating
          // bar above the nav widget instead (the shell mounts it — see
          // routing.instructions.md → Single-column search bar), and this
          // top-left spot belongs to the analytics bar.
          if (FluffyThemes.isColumnMode(context) && searchWidth >= 220)
            Positioned(
              top: 12,
              left: searchLeft,
              width: searchWidth,
              child: WorldMapSearchOverlay(
                filter: widget.controller.filter,
                updateQuery: widget.controller.setQuery,
                // Widen = clear every pill to All (language is fixed by
                // settings; zoom-out is the empty card's other lever).
                onWidenSearch: widget.controller.widenFilters,
                setCefrLevel: widget.controller.setCefrLevel,
                setPartySize: widget.controller.setPartySize,
                setStatus: widget.controller.setStatus,
                results: render.visible,
                onResultTap: widget.controller.flyTo,
                onReset: widget.controller.resetFilters,
                emptyVerdict: widget.controller.emptyVerdict,
                canZoomOut: widget.controller.canZoomOut,
                // "Zoom out" resets to the whole-world view (all the way out,
                // centered over the fullest window of matching pins, #8121),
                // the same as the map's World control — one tap brings the
                // most matches a floor-zoomed viewport can show into view.
                onZoomOut: widget.controller.resetToWorld,
              ),
            ),
          controls,
        ],
      ),
    );
  }
}

/// Wraps a pin layer in the app's shimmer palette while [active] (the L1 warmup
/// — see [WorldMapController.warmingPins]), else renders it untouched.
class _ShimmerLayer extends StatelessWidget {
  final bool active;
  final Widget child;

  const _ShimmerLayer({required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surface,
      child: child,
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
          // The zoom-out floor is viewport-derived (#7813), so read the live
          // one off the controller rather than a constant.
          final canZoomOut =
              zoom == null ||
              WorldMapConstants.canZoomOut(zoom, controller.minZoom);
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
