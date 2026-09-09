import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';

/// The shared chrome for every workspace panel (world_v2): a rounded, elevated
/// surface that floats over the persistent map, with one uniform [margin]. Every
/// panel wraps its content in this so they all read as the same floating card —
/// the left/right column tokens AND the center detail (an activity, a
/// course-wizard step, a public-course preview). Keeping the rounding, elevation
/// and margin in one widget is why they can't drift apart — the focus ring a
/// panel wears on entry ([PanelEntryRing]) rides this same outline for that
/// reason. See `routing.instructions.md`.
class PanelCard extends StatelessWidget {
  final Widget child;

  /// When set, the card is drawn top-aligned at this height instead of
  /// filling its slot — the course card mid-reveal ([CourseCardReveal],
  /// #8866).
  final double? height;

  const PanelCard({super.key, required this.child, this.height});

  /// The margin every panel insets from its allocator slot (and the gap between
  /// adjacent panels is two of these horizontal insets — see [PanelAllocator]'s
  /// `panelGap`). Vertical matches the shell's chrome margin.
  static const EdgeInsets margin = EdgeInsets.symmetric(
    horizontal: 8.0,
    vertical: 12.0,
  );

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      // A shape rather than a plain radius, so a panel holding the entry focus
      // can wear the ring on the card's own outline instead of a second
      // rectangle tracing it from outside ([PanelEntryRing]). Material paints a
      // shape's side in the foreground by default, which is what keeps the
      // stroke off the surface's own edge.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        side: PanelEntryRing.of(context)
            ? FocusRingTapTarget.ringSide(context)
            : BorderSide.none,
      ),
      // Clip the contained surface (a chat, a Scaffold, a card body) to the
      // rounded corners.
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    final height = this.height;
    return Padding(
      padding: margin,
      child: height == null
          ? card
          : Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: card,
              ),
            ),
    );
  }
}

/// Whether the panel below is wearing the entry focus a user-cluster button
/// gave it ([`PanelEntryFocus`](right_panel/panel_entry_focus.dart)), and so
/// should ring. Absent — a panel drawn outside one, such as the centre detail
/// — means no ring. It lives here, beside the card that draws it, so the
/// shared chrome doesn't depend on a right-column widget.
class PanelEntryRing extends InheritedWidget {
  final bool showRing;

  const PanelEntryRing({
    required this.showRing,
    required super.child,
    super.key,
  });

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelEntryRing>()?.showRing ??
      false;

  @override
  bool updateShouldNotify(PanelEntryRing oldWidget) =>
      oldWidget.showRing != showRing;
}
