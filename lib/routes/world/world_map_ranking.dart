import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';

/// The displayed colour-state of a world-map activity pin. Declared
/// lowest-precedence first so `state.index` is the precedence ladder
/// (available < inProgress < joinable < ongoingPending < ongoingActive): when
/// more than one applies the higher one wins the colour. There is no locked
/// state — progression only ranks, never gates (#7186). See
/// world-map.instructions.md ("Pin state").
enum ActivityPinState {
  /// Playable, nothing live and no stars yet — the default. Light brand.
  available,

  /// The learner has fully completed at least one role and has no live session
  /// — their trail. Renders as a fixed-size gold star dot (a super star once
  /// every role is done); partial progress is never shown. Gold.
  inProgress,

  /// An open, live session the learner can join (someone else's) — the map's
  /// preferred unit. Green.
  joinable,

  /// The learner holds a role in a live session, but the room doesn't yet have
  /// enough people for the chat to have started (Ongoing/Pending). Dark brand
  /// purple, hourglass icon.
  ongoingPending,

  /// The learner holds a role in a live session whose roster is full — the
  /// chat has started (Ongoing/Active). Dark brand purple, chat icon.
  ongoingActive;

  /// True for either Ongoing sub-state (world-map.instructions.md, "Pin
  /// state").
  bool get isOngoing =>
      this == ActivityPinState.ongoingPending ||
      this == ActivityPinState.ongoingActive;

  /// True for any live-session state (Ongoing or Joinable) — replaces the old
  /// `state == joined || state == joinable` checks now that Ongoing is two
  /// values.
  bool get isLive => isOngoing || this == ActivityPinState.joinable;

  /// The pin body color. See world-map.instructions.md ("Pin state").
  Color get color => switch (this) {
    ActivityPinState.ongoingPending ||
    ActivityPinState.ongoingActive => AppConfig.primaryColor,
    ActivityPinState.joinable => AppConfig.green,
    ActivityPinState.inProgress => AppConfig.gold,
    ActivityPinState.available => AppConfig.primaryColorLight,
  };

  Color bodyColor(BuildContext context) =>
      this == ActivityPinState.available &&
          Theme.of(context).brightness == Brightness.dark
      ? AppConfig.primaryColorDark
      : color;

  String label(L10n l10n) => switch (this) {
    ActivityPinState.ongoingPending => l10n.ongoingPendingLabel,
    ActivityPinState.ongoingActive => l10n.ongoing,
    ActivityPinState.joinable => l10n.joinableLabel,
    ActivityPinState.inProgress => l10n.inProgressLabel,
    ActivityPinState.available => l10n.availableLabel,
  };

  /// The glyph for this state — the single source of truth for the status
  /// iconography, shared by the map pin, the status filter, the activity
  /// suggestion card, and the start-page CTA row. `inProgress` (Completed) is a
  /// star; the pin renders it as its gold body rather than a glyph, so the
  /// pin's mid-glyph suppresses it (see `world_map_state_dot.dart`).
  IconData get icon => switch (this) {
    ActivityPinState.available => Icons.add,
    ActivityPinState.inProgress => Icons.star,
    ActivityPinState.joinable => Icons.meeting_room,
    ActivityPinState.ongoingPending => Icons.hourglass_bottom,
    ActivityPinState.ongoingActive => Icons.chat_bubble_outline,
  };

  /// The accent used for a large card's border / foreground — the state hue.
  Color get accent => color;

  /// The label text colour: the pin's state colour, except `available` — whose
  /// light-purple fill is too low-contrast for light-purple text, so its label
  /// uses dark purple instead (world-map.instructions.md, "Pin state").
  Color get labelColor =>
      this == ActivityPinState.available ? AppConfig.primaryColor : color;
}

/// The visual weight a pin renders at, filled from the top of the score. The
/// pixel sizes live in [PinSize] (world_map_pin_budget.dart) so every pin-density
/// knob sits in one tunable file.
enum PinTier {
  small,
  mid,
  large;

  double dotHeight(ActivityPinState state) => switch (this) {
    PinTier.small => PinSize.smallDiameter,
    PinTier.mid => PinSize.midDiameter + PinSize.midPointHeight,
    PinTier.large => switch (state) {
      ActivityPinState.joinable ||
      ActivityPinState.ongoingPending => PinSize.largeHeightJoinable,
      _ => PinSize.largeHeight,
    },
  };

  double get dotWidth => switch (this) {
    PinTier.small => PinSize.smallDiameter,
    PinTier.mid => PinSize.midDiameter,
    PinTier.large => PinSize.largeWidth,
  };
}

/// Live signals for one activity derived from Matrix room state: its live-session
/// colour [state] (only ever `joinable`, `ongoingPending`, or `ongoingActive`
/// here — the `inProgress` / `available` states are layered downstream from the
/// learner's stars), a 0..1 [completionFraction] (stars earned toward the
/// activity's total; feeds the `−0.5·completed` ranking term at `>= 1.0`),
/// whether an open session has been [pinged], and a 0..1 [recency] (newest open
/// session first).
class PinSignals {
  final ActivityPinState state;
  final double completionFraction;
  final bool pinged;
  final double recency;
  const PinSignals({
    this.state = ActivityPinState.available,
    this.completionFraction = 0,
    this.pinged = false,
    this.recency = 0,
  });
}

/// The ranking outcome for the pins currently in view: [ordered] is the
/// score-ranked, diversity-capped, trail-reserved candidate list — highest first,
/// truncated to the total on-screen cap `N` (large + mid + small). The geometric
/// placement pass ([placeLargeCards]) consumes [ordered] to decide which large
/// cards actually fit on screen; where placement can't run (unit tests, or the
/// non-column fallback) the [largeIds] / [midIds] getters give the static top-N
/// split by the budgets. No rotation — a static ranking.
///
/// Ranking carries **no tier eligibility gate**: `mid` fills purely by score,
/// and the sole large-tier rule left — the completed trail star is never a large
/// card (`available`/`joinable`/`ongoing` all are) — needs each pin's resolved
/// display state, which only the view holds, so it is applied downstream in
/// [placeLargeCards] via the `largeEligibleIds` the view computes
/// (world-map.instructions.md, "Priority matrix").
class RankingResult {
  /// Candidate ids highest-score-first, after the per-objective diversity cap and
  /// trail reservation, truncated to the total cap `N` (large + mid + small).
  final List<String> ordered;
  final int largeBudget;
  final int midBudget;
  final int smallBudget;

  const RankingResult({
    required this.ordered,
    this.largeBudget = 3,
    this.midBudget = 10,
    this.smallBudget = 0,
  });

  /// The static top-[largeBudget] slice, budget-split only (used where geometric
  /// placement can't run — unit tests / the non-column fallback). Large-tier
  /// eligibility (the completed trail star is never large) is applied by the
  /// view, which alone resolves each pin's display state — see [placeLargeCards].
  List<String> get largeIds => ordered.take(largeBudget).toList();

  /// The [midBudget] candidates after the large slice. Mid has no eligibility
  /// gate — it fills purely by score.
  Set<String> get midIds => ordered.skip(largeBudget).take(midBudget).toSet();
}

/// The relevance band (0..2) for a pin: the next-Mission gradient when the pin
/// sits in one of the learner's in-scope quests, else a plain L2/level-fit floor
/// kept below the in-quest gradient (foreign 0, in-L2 level-appropriate
/// objective-bearing 1.0, other in-L2 0.5). See world-map.instructions.md.
double relevanceBand(
  QuestActivityCard pin, {
  required String? userL2,
  required LanguageLevelTypeEnum? userCefr,
  required ProgressionResolution progression,
}) {
  final gradient = progression.missionGradient(pin.learningObjectiveRefs);
  if (gradient > 0) return gradient;
  final isGlobal = userL2 != null && pin.l2.isNotEmpty && pin.l2 != userL2;
  if (isGlobal) return 0;
  final levelOk = _cefrAtOrBelow(pin.cefr, userCefr);
  if (levelOk && pin.learningObjectiveRefs.isNotEmpty) return 1.0;
  return 0.5;
}

bool _cefrAtOrBelow(String? cefr, LanguageLevelTypeEnum? userCefr) {
  if (userCefr == null) return true;
  if (cefr == null || cefr.isEmpty) return true;
  return LanguageLevelTypeEnum.fromString(cefr).storageInt <=
      userCefr.storageInt;
}

/// Weight of the `multi_person_first_map` penalty (#7435). Large but finite —
/// enough to sink a 3+ role activity below the band ceiling (2) so it recedes to
/// the small-dot tail on a new learner's first map, but a deprioritize, not a
/// gate. A hand-set lever like the rest of the weights (world-map.instructions.md).
const double kMultiPersonFirstMapPenalty = 2.0;

/// Weight of the `dismissed` penalty (#7207/#7245): the learner X'd this
/// activity's large card within the dismissal TTL. Deliberately the same
/// magnitude as `finished` — both mean "demote, keep on the map" — and small
/// enough that it can't push a pin below the render cap `N`. The penalty alone
/// cannot keep a competition-free top scorer out of the large tier, so
/// dismissal is *also* a large-tier eligibility rule in the placement pass
/// ([placeLargeCards]'s `dismissedIds`), like the live-session heavy-tier gate.
const double kDismissedPenalty = 0.5;

/// Rating-count threshold below which an activity counts as NEW (#7993): it
/// takes the TOP of the ratings range (+[kRatingWeight]) and renders a NEW
/// badge — new content gets the benefit of the doubt, not a cold-start
/// penalty. A hand-set lever (world-map.instructions.md).
const int kNewRatingThreshold = 1;

/// Magnitude of the `ratings` term in [pinScore]: the term spans
/// −[kRatingWeight]…+[kRatingWeight] (world-map.instructions.md).
const double kRatingWeight = 2.0;

/// True when this pin has too few ratings to score on them — it renders a NEW
/// badge and [ratingsTerm] gives it the top of the range.
bool isNewActivity(int? ratingCount) =>
    (ratingCount ?? 0) < kNewRatingThreshold;

/// The `ratings` score term (−2…+2): linear in the aggregate up-fraction
/// (`4·avg − 2` at the default weight), except a NEW pin (fewer than
/// [kNewRatingThreshold] ratings) takes +[kRatingWeight]. Ratings only
/// reorder, never hide (world-map.instructions.md).
double ratingsTerm({double? ratingAverage, int? ratingCount}) {
  if (isNewActivity(ratingCount)) return kRatingWeight;
  final avg = (ratingAverage ?? 0.0).clamp(0.0, 1.0);
  return 2 * kRatingWeight * avg - kRatingWeight;
}

/// Weight of the `ongoingActive` state in [pinScore] — strictly above
/// [kOngoingPendingWeight] (both below the `joinable` weight of `3`, so
/// `joinable` still wins the top slot): an active chat with real history
/// should outrank a pending one contending for the same large-card slot.
const double kOngoingActiveWeight = 2.4;

/// Weight of the `ongoingPending` state in [pinScore] — see
/// [kOngoingActiveWeight].
const double kOngoingPendingWeight = 1.6;

/// True when this pin should take the `multi_person_first_map` penalty: the
/// learner has not finished an activity yet ([isNewLearner] — #7999), the
/// activity needs **3+ roles** (unstartable solo — the bot fills exactly one),
/// and it is **not** itself a live session (a joinable/ongoing 3+ session has
/// humans present, so the rationale does not apply). See
/// world-map.instructions.md (#7435).
bool isMultiPersonFirstMap({
  required int? roleCount,
  required bool isNewLearner,
  required PinSignals s,
}) => isNewLearner && (roleCount ?? 0) >= 3 && !s.state.isLive;

/// score = 3*joinable + 2.4*ongoingActive + 1.6*ongoingPending + relevance_band
/// + 0.6*pinged + 0.3*recency - 0.5*finished - 0.5*dismissed -
/// 2*multi_person_first_map + ratings. A live session is the heaviest signal: +3 if the
/// learner can join it (open, someone else's); if they are already in it
/// (ongoing), an active chat (+2.4) outweighs a still-pending one (+1.6) — real
/// history should win a contested large-card slot. `joinable` and `ongoing` are
/// mutually exclusive per pin (the state precedence picks one), so at most one
/// of the three fires. A finished activity (full star row) demotes but stays
/// visible (the trail reservation keeps it on the map), and an X-dismissed one
/// demotes the same way while its TTL runs (#7207/#7245). The multi-person term
/// deprioritizes a 3+ role activity on a new learner's first map (#7435). See
/// world-map.instructions.md.
double pinScore({
  required double band,
  required PinSignals s,
  int? roleCount,
  bool isNewLearner = false,
  bool isDismissed = false,
  double? ratingAverage,
  int? ratingCount,
}) =>
    ratingsTerm(ratingAverage: ratingAverage, ratingCount: ratingCount) +
    3 * (s.state == ActivityPinState.joinable ? 1 : 0) +
    (switch (s.state) {
      ActivityPinState.ongoingActive => kOngoingActiveWeight,
      ActivityPinState.ongoingPending => kOngoingPendingWeight,
      _ => 0.0,
    }) +
    band +
    0.6 * (s.pinged ? 1 : 0) +
    0.3 * s.recency.clamp(0.0, 1.0) -
    0.5 * (s.completionFraction >= 1.0 ? 1 : 0) -
    kDismissedPenalty * (isDismissed ? 1 : 0) -
    kMultiPersonFirstMapPenalty *
        (isMultiPersonFirstMap(
              roleCount: roleCount,
              isNewLearner: isNewLearner,
              s: s,
            )
            ? 1
            : 0);

class _Scored {
  final QuestActivityCard pin;
  final double score;
  const _Scored(this.pin, this.score);
}

/// Rank the in-view pins into a single score-ordered, diversity-capped candidate
/// list ([RankingResult.ordered]), truncated to the total cap `N`
/// ([largeBudget] + [midBudget] + [smallBudget]), with a per-objective diversity
/// cap so one objective can't monopolise the heavy tiers, and a trail reservation
/// ([trailBudget]) that guarantees up to that many of the `N` slots to the
/// highest-ranked in-view *progressed* activities ([progressedIds]) so a
/// learner's trail is never crowded out. Every pin competes — no state/lock gate.
/// The caller filters to the active viewport and re-runs on pan/zoom, so the
/// budgets are per-view. The large/mid/small split (and which large cards
/// actually fit on screen) is decided downstream by [placeLargeCards].
RankingResult rankPins({
  required List<QuestActivityCard> inViewPins,
  required String? userL2,
  required LanguageLevelTypeEnum? userCefr,
  required ProgressionResolution progression,
  required Map<String, PinSignals> signals,
  int largeBudget = 3,
  int midBudget = 10,
  int smallBudget = 0,
  int trailBudget = 0,
  Set<String> progressedIds = const {},
  int maxPerDiversityKey = 2,
  bool isNewLearner = false,
  Set<String> dismissedIds = const {},
}) {
  PinSignals sig(String id) => signals[id] ?? const PinSignals();

  final scored =
      inViewPins.map((p) {
        final band = relevanceBand(
          p,
          userL2: userL2,
          userCefr: userCefr,
          progression: progression,
        );
        return _Scored(
          p,
          pinScore(
            band: band,
            s: sig(p.activityId),
            roleCount: p.roleCount,
            isNewLearner: isNewLearner,
            isDismissed: dismissedIds.contains(p.activityId),
            ratingAverage: p.ratingAverage,
            ratingCount: p.ratingCount,
          ),
        );
      }).toList()..sort((a, b) {
        // activityId tiebreaker: List.sort is unstable, so without it equal-score
        // pins can swap order between settles and flip mid<->small tiers (#8136).
        final byScore = b.score.compareTo(a.score);
        return byScore != 0
            ? byScore
            : a.pin.activityId.compareTo(b.pin.activityId);
      });

  // The full score-ranked list with the per-objective diversity cap applied (not
  // yet truncated to N — the trail reservation needs the tail). Splitting it into
  // large vs mid vs small — and, for large, which actually fit on screen — is the
  // placement pass's job ([placeLargeCards]); ranking stays pure (no geometry).
  final ranked = <String>[];
  final perKey = <String, int>{};
  for (final e in scored) {
    final refs = e.pin.learningObjectiveRefs;
    final key = refs.isNotEmpty ? refs.first : null;
    if (key != null && (perKey[key] ?? 0) >= maxPerDiversityKey) continue;
    ranked.add(e.pin.activityId);
    if (key != null) perKey[key] = (perKey[key] ?? 0) + 1;
  }

  final ordered = _applyTrailReservation(
    ranked: ranked,
    n: largeBudget + midBudget + smallBudget,
    trailBudget: trailBudget,
    progressedIds: progressedIds,
  );

  // No tier eligibility gate lives here any more: `mid` fills purely by score,
  // and the one surviving large-tier rule — the completed trail star is never a
  // large card — needs each pin's resolved display state (which distinguishes a
  // plain `available` pin from a completed one), so the view applies it when it
  // computes `largeEligibleIds` for [placeLargeCards]. See
  // world-map.instructions.md ("Priority matrix").
  return RankingResult(
    ordered: ordered,
    largeBudget: largeBudget,
    midBudget: midBudget,
    smallBudget: smallBudget,
  );
}

/// Cap [ranked] (score-desc) to [n] slots, reserving up to [trailBudget] of them
/// for the highest-ranked progressed activities ([progressedIds]) so the
/// learner's trail is never crowded out by fresher content. The reservation is
/// *within* `N`: a reserved progressed id that falls beyond `N` by score
/// displaces the lowest-ranked chosen id that is not itself progressed, keeping
/// the on-screen count at `N`. The result stays in score order. See
/// world-map.instructions.md ("Goal Progress").
List<String> _applyTrailReservation({
  required List<String> ranked,
  required int n,
  required int trailBudget,
  required Set<String> progressedIds,
}) {
  if (ranked.length <= n) return ranked;

  final chosen = ranked.take(n).toList();
  if (trailBudget <= 0 || progressedIds.isEmpty) return chosen;

  final chosenSet = chosen.toSet();
  final reserved = ranked
      .where(progressedIds.contains)
      .take(trailBudget)
      .toList();

  for (final id in reserved) {
    if (chosenSet.contains(id)) continue;
    // Displace the lowest-ranked chosen id that isn't itself progressed, to keep
    // |chosen| == n. If every chosen id is already progressed, the trail fills
    // the view — nothing to displace.
    final victim = chosen.lastIndexWhere((c) => !progressedIds.contains(c));
    if (victim < 0) break;
    chosenSet.remove(chosen[victim]);
    chosen.removeAt(victim);
    chosenSet.add(id);
  }

  // Re-order the kept ids by the original score ranking.
  return ranked.where(chosenSet.contains).toList();
}

/// The outcome of the geometric placement pass: which pins render as large cards
/// this view ([largeIds] — the focused pin first, if it is a candidate, then the
/// score-ranked candidates whose card footprint fits). See
/// world-map.instructions.md ("Place" step of the pipeline).
class PlacementResult {
  final List<String> largeIds;
  const PlacementResult({required this.largeIds});
}

/// Lay the score-ordered large candidates onto real screen positions, since a
/// large card is a *box*, not a point (world-map.instructions.md, pipeline step
/// 4). Walks [orderedCandidates] top-down and admits one as large only if its
/// card footprint fits the unclaimed [safeArea] (on-screen, not under a panel)
/// and does not overlap a card already placed this pass. The [focusedId] (its
/// detail panel is open) is placed **first** when it is itself a candidate, so
/// its footprint is claimed before the rest and the others yield around it —
/// priority Focused → by score. Focus does not *force* a card: a focused pin that
/// isn't a large candidate stays a dot (with its focus ring), its content shown
/// in the detail panel. A candidate that cannot fit is skipped (it renders as its
/// dot/mid), so the large count is emergent — `min(largeBudget, what fits)`.
///
/// [screenOffsetOf] projects an id to its screen offset (null if it has no point
/// or is off the projection); injecting it keeps this geometry unit-testable
/// without a live map camera. [cardSize] is the large card's footprint; it sits
/// above the pin (the point is the card's bottom-center), matching how
/// flutter_map places an `Alignment.topCenter` marker above its point.
PlacementResult placeLargeCards({
  required List<String> orderedCandidates,
  required String? focusedId,
  required Offset? Function(String id) screenOffsetOf,
  required Size cardSize,
  required Rect safeArea,
  int largeBudget = 3,
  Set<String> largeEligibleIds = const {},
  Set<String> dismissedIds = const {},
}) {
  // The card sits ABOVE its pin: flutter_map places an Alignment.topCenter
  // marker so its box is above the point (the point is the box's bottom-center,
  // a balloon pointing down to the location). So the footprint extends up from
  // the point, centered horizontally.
  Rect cardRectAt(Offset o) => Rect.fromLTWH(
    o.dx - cardSize.width / 2,
    o.dy - cardSize.height,
    cardSize.width,
    cardSize.height,
  );

  // The large-tier eligibility gate: [largeEligibleIds] is every in-view pin
  // whose resolved display state is `available`, `joinable`, or `ongoing` — the
  // one exclusion is the completed trail star (`inProgress`), which is only ever
  // a gold-star dot, never a card (world-map.instructions.md, "Priority matrix").
  // The caller (the view) resolves it, since display state — a plain `available`
  // pin vs a completed one — isn't visible to pure ranking. An X-dismissed pin
  // (#7207) is likewise never large — it falls through to the mid/small pass, so
  // the dismissal demotes rather than removes.
  final candidates = orderedCandidates
      .where((id) => !dismissedIds.contains(id))
      .where(largeEligibleIds.contains)
      .toList();

  // Focused pin goes first when it is a candidate this view, so it claims its
  // footprint and the featured set yields around it. It is not force-added: a
  // focused pin that isn't a candidate never becomes a card here.
  final ordered = <String>[
    if (focusedId != null && candidates.contains(focusedId)) focusedId,
    ...candidates.where((id) => id != focusedId),
  ];

  final largeIds = <String>[];
  final placedRects = <Rect>[];
  for (final id in ordered) {
    if (largeIds.length >= largeBudget) break;
    final o = screenOffsetOf(id);
    if (o == null) continue;
    final rect = cardRectAt(o);
    if (!_fitsWithin(safeArea, rect)) continue;
    if (placedRects.any(rect.overlaps)) continue;
    largeIds.add(id);
    placedRects.add(rect);
  }

  return PlacementResult(largeIds: largeIds);
}

/// Whether [inner] sits entirely inside [outer] (all four edges within).
bool _fitsWithin(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;

/// The teardrop bounding box for a mid pin whose tip (its geographic point) is
/// at screen [tip]: circular head on top (diameter [headDiameter]), point of
/// height [pointHeight] below, so the box's bottom edge is the tip. Mirrors how
/// the mid marker is anchored — tip at the point, box extending up (see
/// `_markerAlignment` in world_map_view.dart).
Rect midPinRect(
  Offset tip, {
  double headDiameter = PinSize.midDiameter,
  double pointHeight = PinSize.midPointHeight,
}) => Rect.fromLTWH(
  tip.dx - headDiameter / 2,
  tip.dy - (pointHeight + headDiameter),
  headDiameter,
  headDiameter + pointHeight,
);

/// The outcome of the mid-pin placement pass ([placeMidPins]): which candidates
/// render as `mid`. A candidate absent from [midIds] was demoted to a small dot
/// — either its footprint overlapped a placed large card (large draws above, so
/// the mid would sit under it) or it overlapped a higher-scored mid pin already
/// placed this pass (world-map.instructions.md, pipeline step 4).
class MidPlacementResult {
  final Set<String> midIds;
  const MidPlacementResult({this.midIds = const {}});
}

/// Lay the score-ordered mid candidates onto real screen positions, mirroring
/// [placeLargeCards]: a candidate earns `mid` only if its teardrop footprint
/// ([midPinRect]) overlaps neither a placed large card ([obstacleRects]) nor a
/// mid pin already placed this pass. One that can't is demoted to a small dot
/// (it falls through to the small tier), so two mid pins never stack and a mid
/// pin never sits under a large card (the two overlaps this pass prevents).
///
/// [focusedId] is placed **first** when it is a candidate, so an open pin keeps
/// its mid spot and lower-scored neighbours yield around it (priority Focused →
/// by score, like the large pass). The count is emergent — `min(midBudget, what
/// fits)`; a demoted candidate frees the walk to keep trying lower-scored ones
/// that do fit. [screenOffsetOf] projects an id to its pin tip (null off the
/// projection); injecting it keeps this geometry unit-testable without a live
/// camera.
MidPlacementResult placeMidPins({
  required List<String> orderedCandidates,
  required String? focusedId,
  required Offset? Function(String id) screenOffsetOf,
  int midBudget = 10,
  List<Rect> obstacleRects = const [],
  double headDiameter = PinSize.midDiameter,
  double pointHeight = PinSize.midPointHeight,
}) {
  // Focused pin first when it is a candidate, so an open pin claims its spot
  // and the rest yield around it (mirrors placeLargeCards).
  final ordered = <String>[
    if (focusedId != null && orderedCandidates.contains(focusedId)) focusedId,
    ...orderedCandidates.where((id) => id != focusedId),
  ];

  final midIds = <String>{};
  final placedRects = <Rect>[];
  for (final id in ordered) {
    if (midIds.length >= midBudget) break;
    final o = screenOffsetOf(id);
    if (o == null) continue;
    final rect = midPinRect(
      o,
      headDiameter: headDiameter,
      pointHeight: pointHeight,
    );
    // Under a placed large card, or over a higher-scored mid pin: demote to a
    // dot (skip — it isn't added to midIds, so it falls to the small tier).
    if (obstacleRects.any(rect.overlaps)) continue;
    if (placedRects.any(rect.overlaps)) continue;
    midIds.add(id);
    placedRects.add(rect);
  }

  return MidPlacementResult(midIds: midIds);
}
