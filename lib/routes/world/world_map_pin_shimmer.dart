import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';

/// The tutorial's gold nudge pulse on a map pin, at the pin's **painted** size.
///
/// [ShimmerBackground] fills its container, and a pin's container is its 48px
/// tap target rather than its 8px painted body — so wrapping a pin directly
/// pulses a disc six times the size of the dot inside it. This constrains the
/// pulse to [size], which callers take from `PinTier.paintedSize`.
class WorldMapPinShimmer extends StatelessWidget {
  final bool enabled;
  final Size size;
  final BorderRadius borderRadius;
  final Widget child;

  const WorldMapPinShimmer({
    required this.enabled,
    required this.size,
    required this.borderRadius,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        SizedBox.fromSize(
          size: size,
          child: ShimmerBackground(
            borderRadius: borderRadius,
            // The same opacity the message tutorial pulses its translate button
            // at — now that the pulse is the size of the pin rather than of its
            // tap box, it reads as a pulse rather than a wash.
            maxOpacity: 0.6,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}
