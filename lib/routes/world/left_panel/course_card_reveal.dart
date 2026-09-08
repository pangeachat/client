import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/routes/world/course_context_bar.dart';
import 'package:fluffychat/routes/world/panel_card.dart';

/// The wide course card's floating chrome, with the card's grow and shrink
/// between it and the context bar (#8866).
///
/// The bar and the card share a header, so the card can mount at the bar's
/// height ([CourseContextBar.height]) and animate up to its slot, and the
/// chevron can run the reverse — [collapse] — before the token is dropped.
/// The bar then takes over at exactly the size the card shrank to, so the swap
/// between two widgets reads as one surface changing height. Below the
/// header the shrinking card shows the same compact peek the narrow sheet
/// rests at, which is the bar's own body.
///
/// [animateIn] is true only on the build the card appeared on with the bar
/// showing before it (the shell compares against its previous build), so a
/// remount that merely swaps the token's section or subpage does not replay
/// the grow, and a cold load has no bar to grow from.
class CourseCardReveal extends StatefulWidget {
  final bool animateIn;
  final Widget child;

  const CourseCardReveal({
    required this.animateIn,
    required this.child,
    super.key,
  });

  /// The reveal above [context], for the card's chevron to shrink it first.
  static CourseCardRevealState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<CourseCardRevealState>();

  @override
  State<CourseCardReveal> createState() => CourseCardRevealState();
}

class CourseCardRevealState extends State<CourseCardReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FluffyThemes.animationDuration,
    value: widget.animateIn ? 0.0 : 1.0,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: FluffyThemes.animationCurve,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateIn) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Shrink the card back to the bar's height. Resolves true once it is
  /// there — the moment to drop the token — and false if the card was torn
  /// down or re-driven mid-way, when there is nothing left to hand the bar.
  Future<bool> collapse() async {
    try {
      await _controller.reverse().orCancel;
      return true;
    } on TickerCanceled {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The slot is the column's full height; the card fills it less
      // PanelCard's own margin. Unbounded (a bare test host) means there is
      // nothing to animate toward.
      final full = constraints.maxHeight.isFinite
          ? constraints.maxHeight - PanelCard.margin.vertical
          : null;
      if (full == null) return PanelCard(child: widget.child);
      return AnimatedBuilder(
        animation: _progress,
        // Always sized, even at rest, so the card's subtree keeps one
        // structure across the animation and never remounts.
        builder: (context, child) => PanelCard(
          height: Tween<double>(
            begin: CourseContextBar.height,
            end: full,
          ).evaluate(_progress),
          child: child!,
        ),
        child: widget.child,
      );
    },
  );
}
