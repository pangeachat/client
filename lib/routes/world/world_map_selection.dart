import 'package:flutter/material.dart';

/// The shared "selected" (focused) treatment for a map pin and a large card
/// (#7349): NO outline. The shape's state-coloured fill darkens slightly and a
/// soft state-coloured glow haloes its whole silhouette, so a selected pin and a
/// selected card read the same, at every tier (world-map.instructions.md,
/// "Focus"). Tuned in one place so the two surfaces stay in lock-step.
abstract class WorldMapSelection {
  static const double _glowBlur = 14.0;
  static const double _glowSpread = 1.5;
  static const double _glowAlpha = 0.75;

  /// How far the fill darkens toward black for the "pressed-in" selected look.
  static const double _darkenAmount = 0.16;

  /// A soft, state-[color]ed glow for the selected shape — the sole selected
  /// affordance now that the outline is gone.
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: _glowAlpha),
      blurRadius: _glowBlur,
      spreadRadius: _glowSpread,
    ),
  ];

  /// Darken a shape's state fill (pin body / card accent frame) for selection.
  static Color darken(Color c) =>
      Color.alphaBlend(Colors.black.withValues(alpha: _darkenAmount), c);
}
