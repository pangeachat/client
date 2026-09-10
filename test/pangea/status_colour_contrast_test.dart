import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';

/// The status colours that carry meaning as FOREGROUND — error text and its
/// icon on the discount-code surface, and the two STT transcript-diff
/// underlines — measured against every surface the light and dark themes put
/// behind them (#8764).
///
/// Fill uses are deliberately absent: a chip or a toggle carrying no text is
/// not held to these ratios, and the bright constants stay in place there.
void main() {
  // WCAG 2.x relative luminance and contrast ratio.
  double luminance(Color c) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  ColorScheme schemeFor(Brightness brightness) => ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: Color(AppSettings.colorSchemeSeedInt.defaultValue),
  );

  /// `surface` plus the four container tones — the darkest of which is the
  /// worst case in the light theme and the one the bright constants fail on.
  List<Color> backgrounds(ColorScheme s) => [
    s.surface,
    s.surfaceContainerLow,
    s.surfaceContainer,
    s.surfaceContainerHigh,
    s.surfaceContainerHighest,
  ];

  void expectClears(
    Color foreground,
    ColorScheme scheme,
    double floor, {
    required String what,
  }) {
    for (final background in backgrounds(scheme)) {
      expect(
        contrast(foreground, background),
        greaterThanOrEqualTo(floor),
        reason:
            '$what on ${background.toARGB32().toRadixString(16)} '
            'measured ${contrast(foreground, background).toStringAsFixed(2)}:1, '
            'under $floor:1',
      );
    }
  }

  // SC 1.4.3 — normal-size text and the icon paired with it.
  const textFloor = 4.5;

  // SC 1.4.11 — the diff underline is a graphical object, not text: per the
  // D10 contract the signal is the underline, and the word itself keeps the
  // inherited text colour.
  const graphicFloor = 3.0;

  test('discount-code error text clears 4.5:1 in both themes', () {
    for (final brightness in Brightness.values) {
      final scheme = schemeFor(brightness);
      expectClears(
        scheme.error,
        scheme,
        textFloor,
        what: 'colorScheme.error ($brightness)',
      );
    }
  });

  test('discount-code success text clears 4.5:1 in both themes', () {
    expectClears(
      AppConfig.completedGreen,
      schemeFor(Brightness.light),
      textFloor,
      what: 'successByTheme light (completedGreen)',
    );
    expectClears(
      AppConfig.success,
      schemeFor(Brightness.dark),
      textFloor,
      what: 'successByTheme dark (success)',
    );
  });

  test('STT diff underlines clear 3:1 in both themes', () {
    final light = schemeFor(Brightness.light);
    expectClears(
      AppConfig.warningDeep,
      light,
      graphicFloor,
      what: 'warningByTheme light (warningDeep)',
    );
    expectClears(
      AppConfig.completedGreen,
      light,
      graphicFloor,
      what: 'successByTheme light (completedGreen)',
    );

    final dark = schemeFor(Brightness.dark);
    expectClears(
      AppConfig.warning,
      dark,
      graphicFloor,
      what: 'warningByTheme dark (warning)',
    );
    expectClears(
      AppConfig.success,
      dark,
      graphicFloor,
      what: 'successByTheme dark (success)',
    );
  });

  // The negative control. If these ever start passing, the floors above have
  // stopped meaning anything and the whole file is vacuous.
  //
  // Measured on the darkest light card rather than on `surface`: `warning`
  // scrapes 3.01:1 on `surface` itself and only fails once there is a card
  // under it (2.44:1), which is exactly why the floors above are checked
  // against every surface rather than just the lightest one.
  test('the bright constants this issue replaced still fail on light', () {
    final card = schemeFor(Brightness.light).surfaceContainerHighest;
    expect(contrast(AppConfig.success, card), lessThan(graphicFloor));
    expect(contrast(AppConfig.warning, card), lessThan(graphicFloor));
    expect(contrast(AppConfig.error, card), lessThan(textFloor));
  });
}
