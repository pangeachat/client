import 'package:flutter/material.dart';

/// Colours derived from a name. The hash lands on one of **12** hues
/// (`sum(codeUnits) % 12`, times 25.5 degrees), so the whole palette is
/// enumerable — every value here was checked against all 12, not sampled.
extension StringColor on String {
  static final _colorCache = <String, Map<double, Color>>{};

  Color _getColor(double lightness, double alpha) {
    var number = 0.0;
    for (var i = 0; i < length; i++) {
      number += codeUnitAt(i);
    }
    number = (number % 12) * 25.5;
    return HSLColor.fromAHSL(alpha, number, 1, lightness).toColor();
  }

  Color _cached(double lightness, double alpha) {
    _colorCache[this] ??= {};
    return _colorCache[this]![lightness] ??= _getColor(lightness, alpha);
  }

  /// A name rendered as **text on a light theme surface**. Opaque, and dark
  /// enough that all 12 hues clear 4.5:1 on both `surface` (worst 6.26:1) and
  /// the darkest card (worst 5.08:1). The previous 0.3/0.2 lightness at 0.75
  /// alpha cleared only 4 of 12 on surface, worst 2.33:1 (#8762).
  Color get nameOnLight => _cached(0.20, 1);

  /// A name rendered as **text on a dark theme surface**: worst 7.88:1 on
  /// `surface`, 5.21:1 on the darkest card. The previous 0.7 at 0.75 alpha
  /// cleared 8 of 12, worst 3.23:1 (#8762).
  Color get nameOnDark => _cached(0.80, 1);

  /// The **fill** behind an avatar's fallback initial. Unchanged: the fill
  /// itself carries no contrast duty, and the initial's legibility comes from
  /// picking its ink with [ReadableInk.readableInk] rather than from darkening
  /// this.
  Color get lightColorAvatar => _cached(0.45, 0.75);
}

extension ReadableInk on Color {
  /// Black or white — whichever contrasts more with this colour once it has
  /// composited over [behind].
  ///
  /// Compared by actual WCAG ratio rather than via
  /// [ThemeData.estimateBrightnessForColor], whose 0.15 luminance threshold
  /// picks black for one of the 12 avatar hues at 4.02:1 — under AA where
  /// white would have given 5.22:1. Choosing by ratio clears 4.5:1 for all 12
  /// in both themes, worst case 4.88:1 (#8762).
  Color readableInk({required Color behind}) {
    final luminance = Color.alphaBlend(this, behind).computeLuminance();
    final againstBlack = (luminance + 0.05) / 0.05;
    final againstWhite = 1.05 / (luminance + 0.05);
    return againstBlack >= againstWhite ? Colors.black : Colors.white;
  }
}
