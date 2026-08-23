import 'package:flutter/widgets.dart';

extension TextScalerFactorExtension on TextScaler {
  /// The factor this scaler applies to text at [fontSize].
  ///
  /// [TextScaler.scale] takes an unscaled **font size**, not an arbitrary
  /// number: the scaler behind `MediaQuery.textScalerOf` forwards it to the
  /// platform, and Android 14+ answers from a non-linear curve where small text
  /// grows more than large text. So the factor at 16pt is not the factor at 1pt
  /// and not whatever `scale(250)` implies about a 250px box.
  ///
  /// Use this wherever a scale factor is needed for something that is not
  /// itself a font size — the height of a box drawn around text, or an API that
  /// takes a plain multiplier — naming the font size the result is meant to
  /// track. See accessibility.instructions.md, Text scaling.
  double factorAt(double fontSize) => scale(fontSize) / fontSize;
}
