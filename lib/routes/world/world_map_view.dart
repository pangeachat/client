import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/discovered_sessions_cache.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_constants.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_pin_label.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_room_extension.dart';
import 'package:fluffychat/routes/world/world_map_search_overlay.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';
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

  const _PinRenderer({
    required this.visible,
    required this.activityIdToStarLevel,
    required this.activityIdToState,
    required this.activityIdToPingStatus,
    required this.activityIdToTier,
    required this.focusedId,
    this.labels = const LabelPlacementResult(),
    this.labelSizes = const {},
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

  bool pingedOf(String id) => activityIdToPingStatus[id] ?? false;

  PinTier tierOf(String id) => activityIdToTier[id] ?? PinTier.small;
}

/// Cached render snapshot for a pin that is animating out of the active set.
class _PinSnapshot {
  final QuestActivityCard card;
  final ActivityPinState state;
  final PinTier tier;
  final bool pinged;
  final ActivityStarLevel starLevel;

  const _PinSnapshot({
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
class _LargeCardSnapshot {
  final QuestActivityCard card;
  final ActivityPinState state;
  final bool pinged;
  final ActivityPlanModel? plan;
  final Room? liveRoom;
  final int starsEarned;
  final List<LargeCardParticipant> participants;
  final int openSlots;

  const _LargeCardSnapshot({
    required this.card,
    required this.state,
    required this.pinged,
    required this.plan,
    required this.liveRoom,
    required this.starsEarned,
    required this.participants,
    required this.openSlots,
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
  static const double _narrowBottomChromeInset = 150.0;

  /// Pins that have left the active set and are animating to scale 0.
  final Map<String, _PinSnapshot> _exiting = {};

  /// Last-known render snapshot of each active non-large pin, used to seed
  /// [_exiting] with the correct visual state when a pin leaves.
  Map<String, _PinSnapshot> _lastActive = {};

  /// Large cards that have left the large tier (demoted, or the dot promoted
  /// past it out of view) and are animating to scale/opacity 0 — mirrors
  /// [_exiting]/[_lastActive] but for [WorldMapLargeCard] (world-map card
  /// pop-in/out; see [WorldMapLargeCardAnimated]).
  final Map<String, _LargeCardSnapshot> _exitingLarge = {};

  /// Last-known render snapshot of each active large card, used to seed
  /// [_exitingLarge] with the correct content when a card leaves.
  Map<String, _LargeCardSnapshot> _lastActiveLarge = {};

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
      ? const Size(
          PinSize.superStarDotDiameter,
          PinSize.superStarDotDiameter,
        )
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

  /// The label text colour: the pin's state colour, except `available` — whose
  /// light-purple fill is too low-contrast for light-purple text, so its label
  /// uses dark purple instead (world-map.instructions.md, "Pin state").
  Color _labelColor(ActivityPinState state) =>
      state == ActivityPinState.available
      ? AppConfig.primaryColor
      : state.color;

  /// The marker alignment that seats a label of [size] on [side] of a mid pin
  /// whose tip is the marker's point — the render-side mirror of [pinLabelRect].
  /// flutter_map's alignment is the pixel position of the point inside the box
  /// ([Marker.computePixelAlignment]); values outside [-1,1] push the box fully
  /// beside the head with no clamping.
  Alignment _labelAlignment(LabelSide side, Size size) {
    final headR = PinSize.midDiameter / 2;
    final left = side == LabelSide.right
        ? -(headR + kPinLabelGap)
        : headR + kPinLabelGap + size.width;
    final top = PinSize.midPointHeight + headR + size.height / 2;
    return Marker.computePixelAlignment(
      width: size.width,
      height: size.height,
      left: left,
      top: top,
    );
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

  /// The activity-name labels for the mid pins the placement pass kept — each a
  /// marker anchored at the pin's point, offset to its chosen side, and
  /// non-interactive (an [IgnorePointer]) so the wide box never swallows a
  /// pin/map tap.
  List<Marker> _labelMarkers(_PinRenderer render) {
    final markers = <Marker>[];
    for (final card in render.nonLargeCards) {
      final id = card.activityId;
      final side = render.labels.sideOf(id);
      final size = render.labelSizes[id];
      if (side == null || size == null) continue;
      markers.add(
        Marker(
          key: ValueKey('label_$id'),
          point: card.point!,
          width: size.width,
          height: size.height,
          alignment: _labelAlignment(side, size),
          child: IgnorePointer(
            child: WorldMapPinLabel(
              title: card.title,
              color: _labelColor(render.stateOf(id)),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  /// Detects newly-gone non-large pins and adds them to [_exiting] using their
  /// last-known render state — **including** a pin promoted to large: its dot
  /// shrinks away in this layer while [WorldMapLargeCardAnimated] grows the new
  /// card in at the same spot ([_largeMarkers]), so promotion reads as one pin
  /// morphing into a card rather than an instant swap. Called at the top of
  /// [build] before the marker layers are constructed — mutates tracking maps
  /// without calling setState.
  void _updateExiting(_PinRenderer render) {
    final currentNonLargeIds = {
      for (final c in render.nonLargeCards) c.activityId,
    };

    // Re-appeared as a (still) non-large pin: cancel any in-progress exit.
    _exiting.removeWhere((id, _) => currentNonLargeIds.contains(id));

    // Anything that was a dot last frame and isn't a dot this frame —
    // genuinely gone, or promoted to large — plays the shrink-out.
    for (final entry in _lastActive.entries) {
      if (!currentNonLargeIds.contains(entry.key) &&
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
          starLevel: render.starLevelOf(card.activityId),
        ),
    };
  }

  /// Mirrors [_updateExiting] for the large tier: a card demoted out of
  /// [currentLarge] (X-dismissed, out-ranked, or no longer fits) plays its
  /// shrink-out in [_exitingLarge] instead of vanishing instantly. Its dot
  /// (mid, if eligible, else small) pops in fresh the same frame, the mirror
  /// image of a promotion.
  void _updateExitingLarge(Map<String, _LargeCardSnapshot> currentLarge) {
    final currentIds = currentLarge.keys.toSet();

    _exitingLarge.removeWhere((id, _) => currentIds.contains(id));

    for (final entry in _lastActiveLarge.entries) {
      if (!currentIds.contains(entry.key) &&
          !_exitingLarge.containsKey(entry.key)) {
        _exitingLarge[entry.key] = entry.value;
      }
    }

    _lastActiveLarge = currentLarge;
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
    // (#7245). Falls through to a fresh compute if nothing has settled yet
    // (e.g. the very first frame).
    final cached = _lastSettledRenderer;
    if (widget.controller.isActivelyMoving && cached != null) {
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
      isNewLearner: widget.controller.isNewLearner,
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
    // Precomputed once (a single rooms pass) so the per-pin star tier is an
    // O(roles) lookup, not an O(rooms) rescan per pin.
    final completedRoles =
        widget.controller.client?.completedRolesByActivity ??
        const <String, Set<String>>{};
    // The full role set per activity, read from the learner's hydrated session
    // plans — the room-derived "all roles" so the super-star doesn't depend on
    // the bbox card projecting `roles` (it may omit them). Same rooms source as
    // completedRoles, so when a role reads completed the total set is populated
    // too. Falls back to the card's roleIds when no plan has hydrated yet.
    final allRoles =
        widget.controller.client?.roleIdsByActivity ??
        const <String, Set<String>>{};

    for (final c in visible) {
      final id = c.activityId;
      if (!tiers.containsKey(id)) continue; // beyond the cap N — not drawn

      final signal = signals[id];
      pings[id] = signal?.pinged ?? false;

      // The learner's completion tier — computed regardless of any live session,
      // so a prior completion stays visible even under a joinable/ongoing pin.
      // A gold star appears ONLY once a full role is done — a plain star (≥1
      // role) or a super star (all roles); partial progress is never shown on a
      // pin (world-map.instructions.md, "Goal Progress").
      final starLevel = starLevelFor(
        completedRoles[id] ?? const {},
        allRoles[id] ?? c.roleIds,
      );
      starLevels[id] = starLevel;

      final sessionState = signal?.state;
      if (sessionState != null) {
        // A live-session state (joinable/joined) wins the colour; the completion
        // star (if any) rides behind the live pin — see WorldMapDot.
        states[id] = sessionState;
      } else {
        // No live session: a completed activity renders AS the star dot (it
        // replaces the plain `available` pin); otherwise the available default.
        states[id] = starLevel == ActivityStarLevel.none
            ? ActivityPinState.available
            : ActivityPinState.inProgress;
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
              discoveredSummary?.largeCardParticipants() ??
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

  /// The mid-pin "num/num" participant counts for `joinable`/`ongoingPending`
  /// (world-map.instructions.md, "Pin display") — derived from the shared
  /// [_sessionParticipants] resolver so they match the large card's row.
  /// Null/null for every other state, or when the counts aren't resolvable yet.
  ({int? filled, int? total}) _participantCounts(
    String activityId,
    ActivityPinState state,
  ) {
    final (:participants, :openSlots) = _sessionParticipants(activityId, state);
    final filled = participants.length;
    final total = filled + openSlots;
    return total > 0
        ? (filled: filled, total: total)
        : (filled: null, total: null);
  }

  /// The learner's own live room for an `ongoingActive` pin (world-map.
  /// instructions.md, "Pin state") — null (badge hidden) for every other
  /// state.
  Room? _unreadRoomFor(String activityId, ActivityPinState state) {
    if (state != ActivityPinState.ongoingActive) return null;
    return widget.controller.client?.activeActivityInstance(activityId);
  }

  /// The rendered small/mid pins, each an individual marker (no clustering).
  /// Tapping any pin opens/focuses the activity in one step (no tap-to-peek).
  /// Small dots are emitted before mid pins so mid always paints on top —
  /// markers later in the list draw over earlier ones, and "small pins should
  /// never show on top of mid pins" (world-map.instructions.md, "Pin display").
  List<Marker> _dotMarkers(_PinRenderer render) {
    // Small dots first, then mid pins, each tier keeping its score order — a
    // stable partition (Dart's List.sort is not guaranteed stable) so mid
    // always paints over small without reshuffling same-tier pins frame to
    // frame.
    final cards = render.nonLargeCards;
    final ordered = [
      ...cards.where((c) => render.tierOf(c.activityId) == PinTier.small),
      ...cards.where((c) => render.tierOf(c.activityId) != PinTier.small),
    ];
    return ordered.map((card) {
        final state = render.stateOf(card.activityId);
        final tier = render.tierOf(card.activityId);
        final box = _markerBox(state, tier);
        final counts = _participantCounts(card.activityId, state);

        return Marker(
          key: ValueKey(card.activityId),
          point: card.point!,
          width: box.width,
          height: box.height,
          alignment: _markerAlignment(state, tier),
          child: WorldMapDot(
            key: ValueKey(card.activityId),
            card: card,
            state: state,
            tier: tier,
            onTap: () => widget.controller.openActivity(card),
            pinged: render.pingedOf(card.activityId),
            starLevel: render.starLevelOf(card.activityId),
            unreadRoom: _unreadRoomFor(card.activityId, state),
            participantsFilled: counts.filled,
            participantsTotal: counts.total,
            isFocused: card.activityId == render.focusedId,
          ),
        );
      }).toList();
  }

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
          alignment: _markerAlignment(p.state, p.tier),
          child: WorldMapDot(
            key: ValueKey('exiting_${p.card.activityId}'),
            card: p.card,
            state: p.state,
            tier: p.tier,
            onTap: () {},
            pinged: p.pinged,
            starLevel: p.starLevel,
            dying: true,
            onExited: () {
              if (mounted) setState(() => _exiting.remove(p.card.activityId));
            },
          ),
        );
      }).toList();

  /// Resolves everything [WorldMapLargeCard] needs for [card] — hydrates the
  /// plan, and sources participants/seats from the right place per state (a
  /// joinable session's room-preview/room, or the learner's own live room for
  /// Ongoing). Shared by [_largeMarkers] (the live layer) and
  /// [_updateExitingLarge] (freezing a snapshot for the card's exit
  /// animation), so both read identical data.
  _LargeCardSnapshot _snapshotLargeCard(QuestActivityCard card, _PinRenderer render) {
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

    return _LargeCardSnapshot(
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
    );
  }

  /// The large featured cards the placement pass fit on screen, rendered
  /// unclustered so they're always visible. Wrapped in
  /// [WorldMapLargeCardAnimated] so a newly-placed card pops in (mirroring a
  /// demoted card's shrink-out in [_exitingLargeMarkers]) instead of snapping
  /// into existence. [currentLarge] is precomputed once per frame in [build]
  /// (and reused by [_updateExitingLarge]) so every card's data is resolved
  /// exactly once.
  List<Marker> _largeMarkers(
    _PinRenderer render,
    Map<String, _LargeCardSnapshot> currentLarge,
  ) {
    const tier = PinTier.large;
    return render.largeCards.map((card) {
      final snap = currentLarge[card.activityId]!;
      return Marker(
        key: ValueKey(card.activityId),
        point: card.point!,
        // Widen by the badge overhang on both sides; the card centres within
        // and the pin stays at the box's horizontal centre, so the tail still
        // lands on the dot while the top-right badge has room to peek.
        width: tier.dotWidth + WorldMapLargeCard.badgeOverhang * 2,
        // The inner Align lets the card hug its own content (each state is a
        // different height: joinable/ongoingPending add the avatar row,
        // ongoingActive adds the message preview + star row). Height here is
        // only a ceiling so the tallest variant isn't clipped; shorter cards
        // don't stretch to fill it. The extra tailHeight reserves room beneath
        // the card for the pin tail; the badgeOverhang reserves room ABOVE
        // (topCenter alignment anchors the box bottom to the pin, so slack
        // lands at the top) for the peeking unread badge.
        height:
            tier.dotHeight(snap.state) +
            WorldMapLargeCard.tailHeight +
            WorldMapLargeCard.badgeOverhang,
        alignment: Alignment.topCenter,
        child: Align(
          // Bottom-align so the card+tail hugs its pin (the tail tip lands on
          // the dot) instead of floating with a gap above it (#7153).
          alignment: Alignment.bottomCenter,
          child: WorldMapLargeCardAnimated(
            key: ValueKey(card.activityId),
            child: WorldMapLargeCard(
              card: snap.card,
              state: snap.state,
              pinged: snap.pinged,
              plan: snap.plan,
              liveRoom: snap.liveRoom,
              starsEarned: snap.starsEarned,
              participants: snap.participants,
              openSlots: snap.openSlots,
              isFocused: card.activityId == render.focusedId,
              onTap: () => widget.controller.openActivity(card),
              onClose: () => widget.controller.dismissLargeCard(card),
            ),
          ),
        ),
      );
    }).toList();
  }

  /// Large cards that have left the tier (X-dismissed, out-ranked, or bumped
  /// by a zoom/placement change) rendered in a separate layer so they can
  /// shrink away without disturbing the live cards — the mirror of
  /// [_exitingMarkers] for the large tier.
  List<Marker> _exitingLargeMarkers() =>
      _exitingLarge.values.where((s) => s.card.point != null).map((snap) {
        const tier = PinTier.large;
        return Marker(
          key: ValueKey('exiting_large_${snap.card.activityId}'),
          point: snap.card.point!,
          width: tier.dotWidth + WorldMapLargeCard.badgeOverhang * 2,
          height:
              tier.dotHeight(snap.state) +
              WorldMapLargeCard.tailHeight +
              WorldMapLargeCard.badgeOverhang,
          alignment: Alignment.topCenter,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: WorldMapLargeCardAnimated(
              key: ValueKey('exiting_large_${snap.card.activityId}'),
              dying: true,
              onExited: () {
                if (mounted) {
                  setState(() => _exitingLarge.remove(snap.card.activityId));
                }
              },
              child: WorldMapLargeCard(
                card: snap.card,
                state: snap.state,
                pinged: snap.pinged,
                plan: snap.plan,
                liveRoom: snap.liveRoom,
                starsEarned: snap.starsEarned,
                participants: snap.participants,
                openSlots: snap.openSlots,
                // No interaction on a card that's on its way out.
                onTap: () {},
                onClose: null,
              ),
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

    final attributionsLeft = 0.0;
    final attributionsBottom = FluffyThemes.isColumnMode(context)
        ? 0.0
        : _narrowBottomChromeInset;

    // Resolve which pins to draw and each one's tier/state/pinged/star-tier once
    // per frame, then lay out the layers from it.
    final render = _resolvePinRender(context);

    // Detect newly-gone pins before building the marker layers.
    _updateExiting(render);

    // Resolve every current large card's data once (shared by the live layer
    // and the exiting-large tracker) and detect newly-gone large cards.
    final currentLarge = {
      for (final c in render.largeCards) c.activityId: _snapshotLargeCard(c, render),
    };
    _updateExitingLarge(currentLarge);

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
          // Activity-name labels for mid pins, above the dots but below the
          // large cards (world-map.instructions.md, "Pin display"; z-order:
          // small < mid < labels < large).
          MarkerLayer(markers: _labelMarkers(render)),
          // Dying pins (a separate layer) so they don't disturb the live pins
          // while animating out.
          MarkerLayer(markers: _exitingMarkers()),
          // Dying large cards (demoted, or bumped out) shrinking away beneath
          // the live layer.
          MarkerLayer(markers: _exitingLargeMarkers()),
          // Large cards (always visible): the featured cards the width affords.
          MarkerLayer(markers: _largeMarkers(render, currentLarge)),
          // Make a background, so attributions stand out in dark mode
          Positioned(
            left: attributionsLeft + 8,
            bottom: attributionsBottom + 8,
            child: Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: const Color.fromARGB(130, 135, 135, 135),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            // On a narrow screen the bottom chrome (nav widget + the search bar
            // riding above it) owns the bottom edge, so lift the attribution
            // above it — otherwise it sits unreadable UNDER the floating rail
            // (#7218 on narrow).
            left: attributionsLeft,
            bottom: attributionsBottom,
            child: RichAttributionWidget(
              // #7218: bottom-LEFT so the attribution and its expand popup don't
              // sit under the bottom-right zoom/World controls (where it was
              // covered and hard to read, especially in dark mode).
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () {},
                ),
                if (dark) TextSourceAttribution('CARTO', onTap: () {}),
              ],
            ),
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
    final l2 = MatrixState.pangeaController.userController.userL2Code;
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
          if (FluffyThemes.isColumnMode(context))
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
