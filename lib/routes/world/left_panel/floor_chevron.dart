import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/layouts/cavity_controls.dart';

/// The single control for a panel that has a rest FLOOR instead of a close —
/// the course panel, on both form factors (#8816). It replaces the X and the
/// back arrow both: the course is never fully dismissed, so there is nothing
/// an X could reveal, and it always has exactly two states to move between.
///
/// The floor differs by form factor, the control does not:
///
/// - **Narrow** the floor is the nav cavity's collapsed peek, and the chevron
///   drives the cavity directly ([CavityControls]).
/// - **Wide** the floor is the [CourseContextBar] in the map's search slot, so
///   collapsing drops the panel's token and the bar takes over naming the
///   scoped map. There is no cavity to drive, hence [onToggleOffCavity].
///
/// It rides the header's LEADING edge in both, where the X used to sit, so the
/// control is in one place whichever state and whichever screen the learner is
/// looking at. Which way it POINTS is per form factor, because the sheet
/// slides and the panel does not — see [ChevronMeaning].
class FloorChevron extends StatelessWidget {
  /// Collapse action for a panel drawn outside the nav cavity (the wide
  /// panel): drop this panel's token so its floor — the context bar — shows.
  /// Null renders nothing, for a host that has neither a cavity nor a floor.
  final VoidCallback? onToggleOffCavity;

  const FloorChevron({this.onToggleOffCavity, super.key});

  @override
  Widget build(BuildContext context) {
    final controls = CavityControls.maybeOf(context);
    final cavityToggle = controls?.toggleCollapse;
    final cavityExpanded = controls?.expanded;
    if (cavityToggle != null && cavityExpanded != null) {
      // Rotation rides the listenable, so a drag rebuilds this icon and not
      // the course card under it.
      return ValueListenableBuilder<bool>(
        valueListenable: cavityExpanded,
        builder: (context, isExpanded, _) => ChevronToggle(
          expanded: isExpanded,
          onTap: cavityToggle,
          // The cavity is a sheet that slides, so the chevron points the way
          // it will travel.
          meaning: ChevronMeaning.motion,
        ),
      );
    }

    final offCavity = onToggleOffCavity;
    if (offCavity == null) return const SizedBox.shrink();
    // Off-cavity this panel is only ever drawn in its expanded state — its
    // collapsed state is a different widget entirely (the bar) — and nothing
    // slides, so it follows the disclosure convention and points UP to say it
    // hides what is open.
    return ChevronToggle(
      expanded: true,
      onTap: offCavity,
      meaning: ChevronMeaning.disclosure,
    );
  }
}

/// Which way a chevron points, and why. The same glyph reads differently
/// depending on whether the surface it controls MOVES or merely appears, so
/// each host says which convention it is under rather than inheriting one
/// (#8816).
enum ChevronMeaning {
  /// Points the way the surface will travel. The nav cavity is a bottom sheet
  /// that slides up to expand and down to collapse, so at its floor the
  /// chevron points UP — the direction the sheet is about to go.
  motion,

  /// Points the way disclosure goes: DOWN reveals more, UP hides it again —
  /// the convention every expander on the web uses. Right for a surface that
  /// appears in place instead of sliding, like the wide course panel, where
  /// "the direction it moves" would describe no motion at all.
  disclosure,
}

/// The chevron glyph and its rotation, shared by the panel header and the
/// [CourseContextBar] so the control cannot drift between the two states it
/// moves between: same button, same size, same place, one rotation apart.
class ChevronToggle extends StatelessWidget {
  /// Whether the thing this controls is currently expanded. Drives both the
  /// rotation and the tooltip.
  final bool expanded;

  /// Which convention the rotation follows — see [ChevronMeaning]. The two are
  /// exact inverses of each other.
  final ChevronMeaning meaning;

  final VoidCallback onTap;

  /// Drop this button from the semantics tree — for a host that is itself one
  /// big button already announcing the same action (the context bar), where a
  /// nested button would announce the tap twice.
  final bool excludeSemantics;

  const ChevronToggle({
    required this.expanded,
    required this.onTap,
    required this.meaning,
    this.excludeSemantics = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final button = IconButton(
      // Flutter's own expand/collapse hints, so a two-way control needs no app
      // string of its own (localization.instructions.md).
      tooltip: expanded
          ? material.expandedIconTapHint
          : material.collapsedIconTapHint,
      onPressed: onTap,
      icon: AnimatedRotation(
        // `expand_more` points down unrotated; a half turn points it up.
        // [ChevronMeaning.motion] points the way the sheet travels (down to
        // collapse), [ChevronMeaning.disclosure] the way disclosure goes
        // (down to reveal) — exact inverses.
        turns: switch (meaning) {
          ChevronMeaning.motion => expanded ? 0.0 : 0.5,
          ChevronMeaning.disclosure => expanded ? 0.5 : 0.0,
        },
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: const Icon(Icons.expand_more),
      ),
    );
    if (excludeSemantics) return ExcludeSemantics(child: button);
    return Semantics(expanded: expanded, child: button);
  }
}
