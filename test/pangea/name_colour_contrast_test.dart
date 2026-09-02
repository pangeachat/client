import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/utils/string_color.dart';

/// The name hash lands on `sum(codeUnits) % 12`, and 'a' is 97 (97 % 12 == 1),
/// so 'a' repeated i+1 times walks every bucket exactly once. The first test
/// proves that rather than assuming it.
final allBuckets = [for (var i = 0; i < 12; i++) 'a' * (i + 1)];

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

// ColorScheme.fromSeed(seedColor: 0xFF8560E0) surfaces. The card is the
// tighter background in both themes, so both are asserted.
const lightSurface = Color(0xFFFEF7FF);
const lightCard = Color(0xFFE6E0E9);
const darkSurface = Color(0xFF141218);
const darkCard = Color(0xFF36343A);

void main() {
  test('the 12 sample names really do cover 12 distinct hues', () {
    final hues = allBuckets.map((n) => n.lightColorAvatar.toARGB32()).toSet();
    expect(hues.length, 12, reason: 'coverage claim of every other test here');
  });

  group('avatar fallback initial clears 4.5:1 on every generated fill', () {
    for (final behind in [Colors.white, Colors.black]) {
      final theme = behind == Colors.white ? 'light' : 'dark';
      test(theme, () {
        for (final name in allBuckets) {
          final fill = name.lightColorAvatar;
          final ink = fill.readableInk(behind: behind);
          // The fill is translucent, so the initial sits on the composite.
          final effective = Color.alphaBlend(fill, behind);
          expect(
            contrast(ink, effective),
            greaterThanOrEqualTo(4.5),
            reason: '$theme theme, fill $fill, ink $ink',
          );
        }
      });
    }
  });

  group('display name clears 4.5:1 as text', () {
    test('light', () {
      for (final name in allBuckets) {
        for (final bg in [lightSurface, lightCard]) {
          expect(
            contrast(name.nameOnLight, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'name ${name.nameOnLight} on $bg',
          );
        }
      }
    });
    test('dark', () {
      for (final name in allBuckets) {
        for (final bg in [darkSurface, darkCard]) {
          expect(
            contrast(name.nameOnDark, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'name ${name.nameOnDark} on $bg',
          );
        }
      }
    });
  });

  test('readableInk picks by ratio, not by the 0.15 luminance threshold', () {
    // allBuckets[8] is 'a' * 9, so bucket 9 -> hue 229.5, the blue where
    // ThemeData.estimateBrightnessForColor picks black at 4.02:1 (under AA)
    // while white gives 5.22:1. Taken from the generator, not hardcoded, so
    // this stays honest if the palette is ever retuned.
    final blue = allBuckets[8].lightColorAvatar;
    final effective = Color.alphaBlend(blue, Colors.white);
    expect(
      ThemeData.estimateBrightnessForColor(effective),
      Brightness.dark,
      reason: 'the stdlib helper would answer "use white ink" here',
    );
    expect(contrast(Colors.black, effective), lessThan(4.5));
    expect(contrast(Colors.white, effective), greaterThan(4.5));
    expect(blue.readableInk(behind: Colors.white), Colors.white);
  });
}
