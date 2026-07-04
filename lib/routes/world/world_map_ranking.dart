import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';

/// The displayed colour-state of a world-map activity pin. Declared
/// lowest-precedence first so `state.index` is the precedence ladder
/// (available < inProgress < joinable < joined): when more than one applies the
/// higher one wins the colour. There is no locked state — progression only
/// ranks, never gates (#7186). See world-map.instructions.md ("Pin state").
enum ActivityPinState {
  /// Playable, nothing live and no stars yet — the default. Light brand.
  available,

  /// The learner has earned ≥1 star and has no live session — their trail. On a
  /// dot this renders as a gold star (size = star fraction); "done" at a full
  /// total. Gold.
  inProgress,

  /// An open, live session the learner can join (someone else's) — the map's
  /// preferred unit. Green.
  joinable,

  /// The learner is already in a live session for this activity. Vibrant brand.
  joined;

  /// The pin body colour. See world-map.instructions.md ("Pin state").
  Color get color => switch (this) {
    ActivityPinState.joined => AppConfig.primaryColor,
    ActivityPinState.joinable => AppConfig.green,
    ActivityPinState.inProgress => AppConfig.gold,
    ActivityPinState.available => AppConfig.primaryColorLight,
  };

  /// The accent used for a large card's border / foreground — the state hue.
  Color get accent => color;
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
    PinTier.mid => PinSize.midDiameter,
    PinTier.large =>
      state == ActivityPinState.joinable
          ? PinSize.largeHeightJoinable
          : PinSize.largeHeight,
  };

  double get dotWidth => switch (this) {
    PinTier.small => PinSize.smallDiameter,
    PinTier.mid => PinSize.midDiameter,
    PinTier.large => PinSize.largeWidth,
  };
}

/// Live signals for one activity derived from Matrix room state: its live-session
/// colour [state] (only ever `joinable` or `joined` here — the `inProgress` /
/// `available` states are layered downstream from the learner's stars), a 0..1
/// [completionFraction] (stars earned toward the activity's total, which sizes the
/// inProgress gold star), whether an open session has been [pinged], and a 0..1
/// [recency] (newest open session first).
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
class RankingResult {
  /// Candidate ids highest-score-first, after the per-objective diversity cap and
  /// trail reservation, truncated to the total cap `N` (large + mid + small).
  final List<String> ordered;
  final int largeBudget;
  final int midBudget;
  final int smallBudget;

  /// The **live-session gate**: when the shown set holds any `joined`/`joinable`
  /// session, the ids eligible for the heavy (`large`/`mid`) tiers — those live
  /// sessions — while every other pin renders `small`, however high it scores.
  /// Null when nothing live is in view (the gate is inert; all pins compete for
  /// the heavy tiers by score). See world-map.instructions.md ("Priority matrix").
  final Set<String>? heavyEligibleIds;

  const RankingResult({
    required this.ordered,
    this.largeBudget = 3,
    this.midBudget = 10,
    this.smallBudget = 0,
    this.heavyEligibleIds,
  });

  bool _heavyEligible(String id) =>
      heavyEligibleIds == null || heavyEligibleIds!.contains(id);

  /// The static top-[largeBudget] eligible for the heavy tier (used where
  /// geometric placement can't run).
  List<String> get largeIds =>
      ordered.where(_heavyEligible).take(largeBudget).toList();

  /// The [midBudget] heavy-eligible candidates just below the large slice.
  Set<String> get midIds =>
      ordered.where(_heavyEligible).skip(largeBudget).take(midBudget).toSet();
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

/// score = 3*joinable + 2*joined + relevance_band + 0.6*pinged + 0.3*recency
/// - 0.5*finished. A live session is the heaviest signal: +3 if the learner can
/// join it (open, someone else's), +2 if they are already in it. `joinable` and
/// `joined` are mutually exclusive per pin (the state precedence picks one), so at
/// most one of the two fires. A finished activity (full star row) demotes but
/// stays visible (the trail reservation keeps it on the map). See
/// world-map.instructions.md ("Priority matrix").
double pinScore({required double band, required PinSignals s}) =>
    3 * (s.state == ActivityPinState.joinable ? 1 : 0) +
    2 * (s.state == ActivityPinState.joined ? 1 : 0) +
    band +
    0.6 * (s.pinged ? 1 : 0) +
    0.3 * s.recency.clamp(0.0, 1.0) -
    0.5 * (s.completionFraction >= 1.0 ? 1 : 0);

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
}) {
  PinSignals sig(String id) => signals[id] ?? const PinSignals();

  final scored = inViewPins.map((p) {
    final band = relevanceBand(
      p,
      userL2: userL2,
      userCefr: userCefr,
      progression: progression,
    );
    return _Scored(p, pinScore(band: band, s: sig(p.activityId)));
  }).toList()..sort((a, b) => b.score.compareTo(a.score));

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

  // The live-session gate: when the shown set holds any joined/joinable session,
  // only those are eligible for the heavy (large/mid) tiers; every other pin is
  // small, however high it scores. Inert (null) when nothing live is in view.
  final liveIds = ordered
      .where(
        (id) =>
            sig(id).state == ActivityPinState.joined ||
            sig(id).state == ActivityPinState.joinable,
      )
      .toSet();

  return RankingResult(
    ordered: ordered,
    largeBudget: largeBudget,
    midBudget: midBudget,
    smallBudget: smallBudget,
    heavyEligibleIds: liveIds.isEmpty ? null : liveIds,
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
  Set<String>? heavyEligibleIds,
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

  // Under the live-session gate only live sessions are eligible for a large card,
  // so a non-live pin — even the focused one — stays a dot
  // (world-map.instructions.md, the heavy-tier gate).
  final candidates = heavyEligibleIds == null
      ? orderedCandidates
      : orderedCandidates.where(heavyEligibleIds.contains).toList();

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
