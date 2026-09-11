import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:fluffychat/config/pangea_colors.dart';

/// WCAG 2 contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const seed = Color(0xFF8560E0);
  final palette = TonalPalette.fromHct(Hct.fromInt(PangeaColors.goldKey));
  Color tone(int t) => Color(palette.get(t));

  final light = PangeaColors.of(Brightness.light);
  final dark = PangeaColors.of(Brightness.dark);
  final lightScheme = ColorScheme.fromSeed(
    seedColor: seed,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final darkScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );

  test('every role is a tone of the gold key colour', () {
    expect(light.gold, tone(40));
    expect(light.goldGraphic, tone(50));
    expect(light.goldContainer, tone(90));
    expect(light.onGoldContainer, tone(10));
    expect(dark.gold, tone(80));
    expect(dark.goldGraphic, tone(80));
    expect(dark.goldContainer, tone(30));
    expect(dark.onGoldContainer, tone(90));
    for (final colors in [light, dark]) {
      expect(colors.goldFixedDim, tone(80));
      expect(colors.onGoldFixed, tone(10));
    }
  });

  test('gold clears 4.5:1 as text on the surface and the card', () {
    for (final surface in [
      lightScheme.surface,
      lightScheme.surfaceContainerHighest,
    ]) {
      expect(contrast(light.gold, surface), greaterThanOrEqualTo(4.5));
    }
    for (final surface in [
      darkScheme.surface,
      darkScheme.surfaceContainerHighest,
    ]) {
      expect(contrast(dark.gold, surface), greaterThanOrEqualTo(4.5));
    }
  });

  test('goldGraphic clears 3:1 as a mark on the surface and the card', () {
    for (final surface in [
      lightScheme.surface,
      lightScheme.surfaceContainerHighest,
    ]) {
      expect(contrast(light.goldGraphic, surface), greaterThanOrEqualTo(3.0));
    }
    for (final surface in [
      darkScheme.surface,
      darkScheme.surfaceContainerHighest,
    ]) {
      expect(contrast(dark.goldGraphic, surface), greaterThanOrEqualTo(3.0));
    }
  });

  test('every fill names an ink that clears 4.5:1 on it', () {
    for (final colors in [light, dark]) {
      expect(
        contrast(colors.onGoldFixed, colors.goldFixedDim),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.onGoldContainer, colors.goldContainer),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('lerp returns the endpoints at 0 and 1', () {
    expect(light.lerp(dark, 0).gold, light.gold);
    expect(light.lerp(dark, 1).gold, dark.gold);
    expect(light.lerp(null, 0.5), same(light));
  });

  test('a theme without the extension still resolves the roles', () {
    expect(ThemeData(brightness: Brightness.dark).pangea.gold, dark.gold);
    expect(ThemeData().pangea.gold, light.gold);
  });
}
