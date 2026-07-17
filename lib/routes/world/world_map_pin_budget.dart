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
    PinBudget(large: 0, mid: 4, small: 30, trail: 8),
  ), //    N=14 (no large)
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

/// Tier pixel sizes — also tuned here so all pin-density knobs live in one file.
abstract class PinSize {
  /// Small dot — intentionally tiny, Google-Maps style (was 18px before the
  /// maps-like redesign).
  static const double smallDiameter = 8.0;

  /// Mid pin (activity-type glyph) diameter — the circular "head" of the
  /// teardrop marker.
  static const double midDiameter = 44.0;

  /// Extra height below the mid pin's circular head for the teardrop's
  /// pointed tip, which sits at the pin's geographic anchor (Figma
  /// `Activity pin v3`; world-map.instructions.md, "Pin display"). Small pins
  /// stay a plain circle and don't use this.
  static const double midPointHeight = 10.0;

  /// No longer a separate reserved row: a mid pin's "num/num" participant
  /// count (joinable / ongoing-pending only) now stacks inside the circular
  /// head under its icon glyph (world-map.instructions.md, "Pin display"), so
  /// the marker box needs no extra height below the teardrop's point. Kept at
  /// 0 (rather than removed) so the box-height/anchor math in
  /// `world_map_ranking.dart`/`world_map_view.dart` stays a single formula.
  static const double midLabelHeight = 0.0;

  /// Large card width.
  static const double largeWidth = 260.0;

  /// Large card height — taller when a joinable session shows its participant row.
  static const double largeHeight = 150.0;
  static const double largeHeightJoinable = 184.0;

  /// Diameter of the completed-activity **star dot** — a gold [Icons.star] (one
  /// role done) or, one size up, a [Icons.hotel_class] **super star** (all roles)
  /// in a base-colour circle, drawn in place of (or, under a live pin, behind) a
  /// coloured pin body (world-map.instructions.md, "Goal Progress"). Fixed:
  /// progress on a pin is binary (a role is complete or it isn't), never a
  /// partial fraction, so the old grow-with-fill min/max sizing is gone. The
  /// super star is a touch larger to carry its busier star-on-a-star glyph.
  static const double starDotDiameter = 20.0;
  static const double superStarDotDiameter = 24.0;

  /// Glyph size inside the regular / super star circle.
  static const double starGlyphSize = 16.0;
  static const double superStarGlyphSize = 20.0;
}
