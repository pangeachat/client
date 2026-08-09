import 'package:flutter/material.dart';

import 'package:fluffychat/routes/home/pangea_logo_svg.dart';

/// The Pangea Chat brand mark as a tappable button.
///
/// Wraps the logo in a Material [IconButton] so it gets the full set of
/// Material interaction states for free — hover overlay, pressed ripple, and
/// focus highlight — i.e. it behaves like a standard Material button. Used for
/// the World / home slot in the desktop rail and the mobile bottom bar, and
/// reusable anywhere the branded icon needs Material affordances.
class PangeaIconButton extends StatelessWidget {
  final VoidCallback onPressed;

  /// Tints the mark with the primary colour (the selected/active treatment).
  final bool selected;

  /// Logical size of the mark itself; the Material hit target/overlay grows
  /// around it per [IconButton] conventions.
  final double size;

  final String? tooltip;

  const PangeaIconButton({
    required this.onPressed,
    this.selected = false,
    this.size = 24.0,
    this.tooltip,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      icon: PangeaLogoSvg(width: size, forceColor: color),
    );
  }
}
