import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The displayed colour-state of a world-map activity pin. There is no locked
/// state: progression only ranks, never gates (#7186). Completion is not a
/// state either — it renders as a progress fill carried by
/// [PinSignals.completionFraction], orthogonal to the colour. See
/// world-map.instructions.md.
enum ActivityPinState {
  unlocked,
  joinable;

  /// unlocked = purple (available), joinable = green (an open session to join).
  Color get color {
    switch (this) {
      case ActivityPinState.joinable:
        return const Color(0xFF34A853);
      case ActivityPinState.unlocked:
        return const Color(0xFF7B61FF);
    }
  }

  Color get accent {
    switch (this) {
      case ActivityPinState.joinable:
        return AppConfig.green;
      case ActivityPinState.unlocked:
        return AppConfig.purple;
    }
  }
}

/// The visual weight a pin renders at, filled from the top of the score.
enum PinTier {
  small,
  mid,
  large;

  double dotHeight(ActivityPinState state) => switch (this) {
    PinTier.small => 18.0,
    PinTier.mid => 44.0,
    PinTier.large => state == ActivityPinState.joinable ? 184.0 : 150.0,
  };

  double get dotWidth => switch (this) {
    PinTier.small => 18.0,
    PinTier.mid => 44.0,
    PinTier.large => 260.0,
  };
}

/// Live signals for one activity, derived from Matrix room state: its colour
/// [state], a 0..1 [completionFraction] (stars earned toward the activity's
/// total, drawn as the inner fill; a full row demotes via the score but never
/// hides the pin), whether an open session has been [pinged], and a 0..1
/// [recency] (newest open session first).
class PinSignals {
  final ActivityPinState state;
  final double completionFraction;
  final bool pinged;
  final double recency;
  const PinSignals({
    this.state = ActivityPinState.unlocked,
    this.completionFraction = 0,
    this.pinged = false,
    this.recency = 0,
  });
}

/// The ranking outcome for the pins currently in view: [ordered] is the
/// score-ranked, diversity-capped candidate list (large + mid budget), highest
/// first. The geometric placement pass ([placeLargeCards]) consumes [ordered] to
/// decide which large cards actually fit on screen; where placement can't run
/// (unit tests, or the non-column fallback) the [largeIds] / [midIds] getters
/// give the static top-N split by the budgets. No rotation — a static ranking.
class RankingResult {
  /// Candidate ids highest-score-first, after the per-objective diversity cap,
  /// truncated to the combined large + mid budget.
  final List<String> ordered;
  final int largeBudget;
  final int midBudget;
  const RankingResult({
    required this.ordered,
    this.largeBudget = 3,
    this.midBudget = 10,
  });

  /// The static top-[largeBudget] (used where geometric placement can't run).
  List<String> get largeIds => ordered.take(largeBudget).toList();

  /// The [midBudget] candidates just below the large slice.
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

/// score = 3*joinable + relevance_band + 0.6*pinged + 0.3*recency - 0.5*finished.
/// Joinable is the heaviest term (joining a live session is the map's goal); a
/// finished activity (full star row) demotes but stays visible.
double pinScore({required double band, required PinSignals s}) =>
    3 * (s.state == ActivityPinState.joinable ? 1 : 0) +
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
/// list ([RankingResult.ordered]), truncated to the large + mid budget, with a
/// per-objective diversity cap so one objective can't monopolise the featured
/// set. Every pin competes — no state/lock gate; a finished pin is demoted by its
/// score, not excluded. The caller filters to the active viewport and re-runs on
/// pan/zoom, so the budgets are per-view. The large/mid split (and which large
/// cards actually fit on screen) is decided downstream by [placeLargeCards].
RankingResult rankPins({
  required List<QuestActivityCard> inViewPins,
  required String? userL2,
  required LanguageLevelTypeEnum? userCefr,
  required ProgressionResolution progression,
  required Map<String, PinSignals> signals,
  int largeBudget = 3,
  int midBudget = 10,
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

  // One score-ranked, diversity-capped candidate list. Splitting it into large
  // vs mid — and, for large, which actually fit on screen — is the placement
  // pass's job ([placeLargeCards]); ranking stays pure (no geometry).
  final ordered = <String>[];
  final perKey = <String, int>{};
  for (final e in scored) {
    if (ordered.length >= largeBudget + midBudget) break;
    final refs = e.pin.learningObjectiveRefs;
    final key = refs.isNotEmpty ? refs.first : null;
    if (key != null && (perKey[key] ?? 0) >= maxPerDiversityKey) continue;
    ordered.add(e.pin.activityId);
    if (key != null) perKey[key] = (perKey[key] ?? 0) + 1;
  }

  return RankingResult(
    ordered: ordered,
    largeBudget: largeBudget,
    midBudget: midBudget,
  );
}

/// The outcome of the geometric placement pass: which pins render as large cards
/// this view ([largeIds] — the tap-selected pin, always, plus the featured
/// candidates whose card footprint fits), and the non-large pins to drop from the
/// cluster layer because they sit under a placed card ([suppressedIds]), so no
/// count bubble ever forms beneath a card. See world-map.instructions.md ("Place"
/// step of the pipeline).
class PlacementResult {
  final List<String> largeIds;
  final Set<String> suppressedIds;
  const PlacementResult({required this.largeIds, required this.suppressedIds});
}

/// Lay the score-ordered large candidates onto real screen positions, since a
/// large card is a *box*, not a point (world-map.instructions.md, pipeline step
/// 4). Walks [orderedCandidates] top-down and admits one as large only if its
/// card footprint fits the unclaimed [safeArea] (on-screen, not under a panel)
/// and does not overlap a card already placed this pass. The tap-[selectedId] is
/// reserved first and never yields — it is the deliberate peek — so the priority
/// is Selected → Featured: featured cards yield around it. A featured candidate
/// that cannot fit is skipped (it renders as its dot/mid), so the large count is
/// emergent — `min(largeBudget, what fits)`. Long-tail pins whose point falls
/// inside a placed card come back in [PlacementResult.suppressedIds].
///
/// [screenOffsetOf] projects an id to its screen offset (null if it has no point
/// or is off the projection); injecting it keeps this geometry unit-testable
/// without a live map camera. [cardSize] is the large card's footprint; it sits
/// above the pin (the point is the card's bottom-center), matching how
/// flutter_map places an `Alignment.topCenter` marker above its point.
PlacementResult placeLargeCards({
  required List<String> orderedCandidates,
  required String? selectedId,
  required Iterable<String> visibleIds,
  required Offset? Function(String id) screenOffsetOf,
  required Size cardSize,
  required Rect safeArea,
  int largeBudget = 3,
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

  final largeIds = <String>[];
  final placedRects = <Rect>[];

  // Selected is reserved first and never yields — a deliberate peek always shows
  // large, even spilling an edge (the camera-nudge that keeps it fully on-screen
  // is a separate concern). Its footprint still blocks featured cards and
  // suppresses the long tail beneath it.
  if (selectedId != null) {
    largeIds.add(selectedId);
    final o = screenOffsetOf(selectedId);
    if (o != null) placedRects.add(cardRectAt(o));
  }

  // Featured candidates fill the remaining budget, highest score first, each
  // admitted only if it fits the safe area and clears every placed card.
  for (final id in orderedCandidates) {
    if (largeIds.length >= largeBudget) break;
    if (id == selectedId) continue;
    final o = screenOffsetOf(id);
    if (o == null) continue;
    final rect = cardRectAt(o);
    if (!_fitsWithin(safeArea, rect)) continue;
    if (placedRects.any(rect.overlaps)) continue;
    largeIds.add(id);
    placedRects.add(rect);
  }

  // Drop long-tail pins that sit under a placed card from the cluster layer, so
  // a count bubble never forms beneath a card.
  final suppressed = <String>{};
  if (placedRects.isNotEmpty) {
    final large = largeIds.toSet();
    for (final id in visibleIds) {
      if (large.contains(id)) continue;
      final o = screenOffsetOf(id);
      if (o == null) continue;
      if (placedRects.any((r) => r.contains(o))) suppressed.add(id);
    }
  }

  return PlacementResult(largeIds: largeIds, suppressedIds: suppressed);
}

/// Whether [inner] sits entirely inside [outer] (all four edges within).
bool _fitsWithin(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;
