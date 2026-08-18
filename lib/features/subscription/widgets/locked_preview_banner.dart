import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/widgets/locked_shimmer_box.dart';
import 'package:fluffychat/features/subscription/widgets/unlock_button.dart';

/// A skeleton strip with the gold [UnlockButton] centered on it — the shape a
/// subscription gate takes wherever the content it stands in for is a single
/// band: inside a message bubble, and over the writing-assistance corrections.
///
/// The button sizes the stack and the block fills it, so the skeleton stays
/// wider than the pill for any length of localized label — [inset] is how far
/// past the pill it extends.
class LockedPreviewBanner extends StatelessWidget {
  final String label;
  final double fontSize;
  final EdgeInsetsGeometry inset;
  final EdgeInsetsGeometry buttonPadding;

  const LockedPreviewBanner({
    super.key,
    required this.label,
    this.fontSize = 14.0,
    this.inset = const EdgeInsets.symmetric(horizontal: 32.0, vertical: 6.0),
    this.buttonPadding = const EdgeInsets.symmetric(
      horizontal: 16.0,
      vertical: 8.0,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Positioned.fill(
          child: LockedShimmerBox(
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Padding(
          padding: inset,
          child: UnlockButton(
            label: label,
            fontSize: fontSize,
            padding: buttonPadding,
            showStars: true,
          ),
        ),
      ],
    );
  }
}
