/// **The one place to tune world-map pin density and sizes.**
///
/// The map is Google-Maps-sparse: how many pins show, and how many are cards, is
/// driven entirely by the **available visible-map width** (the viewport minus any
/// open side panels). [budgetForWidth] maps that width to a [PinBudget] — a total
/// cap `N` split into `large` / `mid` / `small` caps that **sum to `N`**, plus a
/// `trail` count: how many of the `N` slots are reserved for the learner's in-view
/// progressed activities so their trail is never crowded out. As the width shrinks
/// the heavy tiers empty first (large, then mid), leaving only small dots on a
/// narrow / panel-crowded / mobile layout. There is no clustering; pins past `N`
/// are simply not drawn.
///
/// Everything here is a **tunable starting point** — adjust the breakpoints,
/// counts, and sizes freely; this file is the single source of truth. See
/// `world-map.instructions.md` ("Pin display" / "Priority matrix" / "Scale
/// boundary").
library;

import 'package:flutter/material.dart' show Size, kMinInteractiveDimension;

/// A resolved per-view pin budget: the constituent tier caps plus the trail
/// reservation. [total] (`N`) is the sum of the tier caps.
class PinBudget {
  final int large;
  final int mid;
  final int small;

  /// How many of the `N` slots are reserved for the highest-ranked in-view
  /// *progressed* activities (any stars earned) so the learner's trail is never
  /// crowded out by fresher content. A reservation *within* `N`, not added on top
  /// — keep it `<= total`. See `world-map.instructions.md` ("Goal Progress").
  final int trail;

  const PinBudget({
    required this.large,
    required this.mid,
    required this.small,
    required this.trail,
  });

  /// The total on-screen pin cap `N` for this view.
  int get total => large + mid + small;
}

/// One row of the width breakpoint table: applies when the available visible-map
/// width is `>= minWidth` (and no wider row matched first).
class PinBudgetBreakpoint {
  final double minWidth;
  final PinBudget budget;
  const PinBudgetBreakpoint(this.minWidth, this.budget);
}

/// The width breakpoint table, **widest first** — the first row whose [minWidth]
/// the available visible-map width meets wins. Widths are logical px of the map
/// area NOT covered by side panels. TUNE FREELY (counts and breakpoints both).
///
/// Design notes encoded in the starting values:
///  - large cards only appear at `>= 600` px of visible width;
///  - below `360` px (mobile / many panels open) it is dots only (no mid either);
///  - each row's caps sum to its `N` (shown in the trailing comment).
const List<PinBudgetBreakpoint> kPinBudgetBreakpoints = [
  PinBudgetBreakpoint(
    1500,
    PinBudget(large: 3, mid: 10, small: 80, trail: 20),
  ), // N=30
  PinBudgetBreakpoint(
    1100,
    PinBudget(large: 3, mid: 8, small: 80, trail: 16),
  ), //  N=25
  PinBudgetBreakpoint(
    800,
    PinBudget(large: 3, mid: 6, small: 70, trail: 12),
  ), //   N=20
  PinBudgetBreakpoint(
    600,
    PinBudget(large: 1, mid: 5, small: 50, trail: 10),
  ), //   N=17 (large appears)
  PinBudgetBreakpoint(
    360,
    PinBudget(large: 1, mid: 4, small: 30, trail: 8),
  ), //    N=14 (one large)
  PinBudgetBreakpoint(
    0,
    PinBudget(large: 0, mid: 0, small: 10, trail: 5),
  ), //       N=8  (dots only)
];

/// The pin budget for the given available visible-map [width] (logical px — the
/// viewport minus open side panels). Stepped, not interpolated: it returns the
/// first table row the width meets.
PinBudget budgetForWidth(double width) {
  for (final bp in kPinBudgetBreakpoints) {
    if (width >= bp.minWidth) return bp.budget;
  }
  return kPinBudgetBreakpoints.last.budget;
}

/// The map's large tier as **activity cards**: the course plan's own card,
/// squared up, standing on the completed stamp at the real location. False
/// draws the classic large callout cards instead.
const bool kMapActivityCards = true;

/// Whether a completed stamp webs out the words the learner used in that
/// activity, as gold chips around it. Off: none of the word web is computed
/// or drawn.
const bool kStampWordWeb = false;

/// Tier pixel sizes — also tuned here so all pin-density knobs live in one file.
abstract class PinSize {
  /// The activity card a large pin draws under [kMapActivityCards]: its
  /// width, its card height (photo [mapCardImageHeight] + text) and the tail
  /// under it. A played card's coin rides its photo (#9559), so it needs no
  /// room of its own.
  static const double mapCardWidth = 132.0;
  static const double mapCardHeight = 152.0;
  static const double mapCardImageHeight = 80.0;
  static const double mapCardTail = 10.0;

  /// Room around an activity card, on its sides and above it, for its focus
  /// ring.
  static const double mapCardFocusGutter = 4.0;

  /// The corner radius of an activity card.
  static const double mapCardRadius = 12.0;

  /// The marker box of an activity card: the card, its tail, and the
  /// focus gutter on the sides and top. The one size every layer and
  /// placement pass uses for the card.
  static const Size mapCardBox = Size(
    mapCardWidth + mapCardFocusGutter * 2,
    mapCardHeight + mapCardTail + mapCardFocusGutter,
  );

  /// Small dot — intentionally tiny, Google-Maps style (was 18px before the
  /// maps-like redesign).
  static const double smallDiameter = 8.0;

  /// The tappable box around a **dot-shaped** marker — a small-tier dot, or the
  /// completed trail star at any tier (`PinTier.isDot`). The dot itself stays
  /// [smallDiameter] / [starDotDiameter] (world-map.instructions.md: "a
  /// deliberately small dot"); only its flutter_map marker box — and so its hit
  /// target and semantics rect — is padded out, centred on the same anchor, to
  /// Material's minimum interactive dimension (48 logical px, above WCAG
  /// 2.5.5's 44) so a dot is tappable on a phone without zooming in until it
  /// earns a mid pin (#7688). Overlapping dots overlap their targets too — a
  /// tap between two dots lands on the one drawn on top, which the issue
  /// accepted over dots that take several tries to hit.
  static const double dotTouchTarget = kMinInteractiveDimension;

  /// Mid pin (activity-type glyph) diameter — the circular "head" of the
  /// teardrop marker.
  static const double midDiameter = 44.0;

  /// Extra height below the mid pin's circular head for the teardrop's
  /// pointed tip, which sits at the pin's geographic anchor (Figma
  /// `Activity pin v3`; world-map.instructions.md, "Pin display"). Small pins
  /// stay a plain circle and don't use this. A mid pin's "num/num" participant
  /// count (joinable / ongoing-pending only) stacks inside the circular head
  /// under its icon glyph, so the marker box is just head + point — no reserved
  /// row below the tip, and no outside activity-name label any more.
  static const double midPointHeight = 10.0;

  /// Large card width bounds. Cards size to their content (title + info row)
  /// between these — [largeMinWidth] keeps a short-title card from collapsing to
  /// a sliver, [largeWidth] caps a long one (its title wraps to two lines and
  /// then ellipsizes rather than growing past it). The marker box is always the
  /// max width and centres the card, so the tail still lands on the pin.
  static const double largeMinWidth = 150.0;
  static const double largeWidth = 260.0;

  /// Large card height — taller when a joinable session shows its participant row.
  static const double largeHeight = 150.0;
  static const double largeHeightJoinable = 184.0;

  /// Diameter of the completed stamp on the map, about 2/3 of a mid pin's
  /// head — drawn in place of (or, under a live pin, behind) a coloured pin
  /// body (world-map.instructions.md, "Goal Progress"). Fixed: a stamp marks a
  /// saved session, never a partial fraction.
  static const double starDotDiameter = 30.0;
}
