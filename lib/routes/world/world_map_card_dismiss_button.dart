import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// The dismiss X on a map card, as a corner badge: a close glyph on a
/// surface-coloured disc with a white ring, so it reads against both the
/// card and the map behind it. Tapping it demotes the card. It sits ABOVE the
/// card's content in the card's stack, and the gesture arena routes its tap
/// here rather than to the card's open-on-tap beneath.
class WorldMapCardDismissButton extends StatelessWidget {
  /// Diameter — small enough to nestle in a card's corner, big enough to be a
  /// real tap target on a touch screen.
  static const double size = 30.0;

  final VoidCallback onPressed;

  const WorldMapCardDismissButton({required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Pointer-only: the cards draw inside the ExcludeSemantics'd map subtree,
    // which hides this button from assistive tech but NOT from Tab traversal —
    // leaving it in makes an invisible dead Tab stop per visible card (2.4.7).
    // The keyboard path to pins is the mirror layer's single roving stop
    // (world-map.instructions.md → Keyboard access).
    return ExcludeFocus(
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.close),
        iconSize: 18,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: size, minHeight: size),
        tooltip: L10n.of(context).close,
        color: theme.colorScheme.onSurfaceVariant,
        style: IconButton.styleFrom(
          // Without this the button's box is the 48px padded tap target, not the
          // disc — it would overhang the card and swallow taps on the content
          // it paints over.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: theme.colorScheme.surface,
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white, width: 1.5),
          ),
        ),
      ),
    );
  }
}
