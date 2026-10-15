import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';

/// The completed-activity **trail marker** on a pin: the [CompletedStamp] at
/// [PinSize.starDotDiameter], so a saved activity reads the same on its card
/// and its pin (world-map.instructions.md, "Pin state" / "Goal Progress").
/// Shared by the pin ([WorldMapDot]) and the large card ([WorldMapLargeCard]).
class WorldMapStarDot extends StatelessWidget {
  const WorldMapStarDot({super.key});

  @override
  Widget build(BuildContext context) =>
      const CompletedStamp(size: PinSize.starDotDiameter);
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

  const CompletionStarBelowTip({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    const radius = PinSize.starDotDiameter / 2;
    return Stack(
      clipBehavior: Clip.none,
      // Bottom-centre aligns the star's base to the tip; nudging it down a touch
      // past its own radius tucks the top behind the tip and peeks the rest below
      // (centre lands ~3px under the tip — the same relationship the mid pin has
      // to its teardrop point).
      alignment: Alignment.bottomCenter,
      children: [
        Transform.translate(
          offset: const Offset(0, radius + 3),
          child: const IgnorePointer(child: WorldMapStarDot()),
        ),
        child,
      ],
    );
  }
}
