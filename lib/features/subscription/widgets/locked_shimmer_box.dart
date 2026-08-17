import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/shimmer_box.dart';

/// A [ShimmerBox] in the shared locked-preview palette: a translucent block
/// standing in for a piece of content a subscription would unlock, sweeping in
/// the theme's primary.
///
/// Every subscription gate draws its skeleton from these, so the gates differ
/// only in how the blocks are arranged (#7929).
class LockedShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  /// Overrides [placeholderColor] — for a block standing in for content that
  /// is itself tinted, like the practice page's example message.
  final Color? baseColor;

  const LockedShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.baseColor,
  });

  /// The fill a placeholder block wears: a wash of the surface's opposite, so
  /// it reads as absent content in either brightness.
  static Color placeholderColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white.withAlpha(50)
      : Colors.black.withAlpha(50);

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      baseColor: baseColor ?? placeholderColor(context),
      highlightColor: Theme.of(context).colorScheme.primary,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}
