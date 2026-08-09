import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';

/// The completed-activity **trail marker**: a gold [Icons.star] (one role done)
/// or a slightly larger [Icons.hotel_class] **super** star (all roles) centred
/// in a base-colour circle, so it reads as a callout on the map rather than a
/// bare glyph (world-map.instructions.md, "Pin state" / "Goal Progress").
/// Shared by the pin ([WorldMapDot]) and the large card ([WorldMapLargeCard]) so
/// a completed activity's star looks identical wherever it shows.
class WorldMapStarDot extends StatelessWidget {
  final bool superStar;

  const WorldMapStarDot({required this.superStar, super.key});

  /// The circle diameter for a [superStar] / regular star — also what the
  /// marker-box math and focus ring size to (the super star is the larger).
  static double diameterFor(bool superStar) =>
      superStar ? PinSize.superStarDotDiameter : PinSize.starDotDiameter;

  @override
  Widget build(BuildContext context) => Container(
    width: diameterFor(superStar),
    height: diameterFor(superStar),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      shape: BoxShape.circle,
      boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
    ),
    child: Icon(
      superStar ? Icons.hotel_class : Icons.star,
      size: superStar ? PinSize.superStarGlyphSize : PinSize.starGlyphSize,
      color: AppConfig.gold,
    ),
  );
}

/// Places a completion [WorldMapStarDot] BEHIND [child], peeking out from
/// directly beneath the child's bottom-centre tip — the pin/caret point that
/// lands on the map location. The star's top tucks behind the tip and the rest
/// peeks below; non-interactive. Used identically by a mid pin (its teardrop
/// tip) and a large card (its caret tip), so a completed activity's trail star
/// sits the same way under either, with the live pin/card stacked on top of it
/// (world-map.instructions.md, "Goal Progress" — the star dot stays visible even
/// when a joinable/ongoing pin is stacked over it).
class CompletionStarBelowTip extends StatelessWidget {
  final Widget child;
  final bool superStar;

  const CompletionStarBelowTip({
    required this.child,
    required this.superStar,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final radius = WorldMapStarDot.diameterFor(superStar) / 2;
    return Stack(
      clipBehavior: Clip.none,
      // Bottom-centre aligns the star's base to the tip; nudging it down a touch
      // past its own radius tucks the top behind the tip and peeks the rest below
      // (centre lands ~3px under the tip — the same relationship the mid pin has
      // to its teardrop point).
      alignment: Alignment.bottomCenter,
      children: [
        Transform.translate(
          offset: Offset(0, radius + 3),
          child: IgnorePointer(child: WorldMapStarDot(superStar: superStar)),
        ),
        child,
      ],
    );
  }
}
