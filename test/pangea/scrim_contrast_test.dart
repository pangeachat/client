import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'contrast_ratio.dart';

/// The scrim exists to be lightened — #9148 lightened it once already, and the
/// next "still too dark" report will lighten it again. In light mode that has
/// a floor: the round toolbar buttons float on the scrim with nothing else
/// behind them, so `toolbarButtonFill` owes 3:1 against it, and the pale
/// light-mode fill runs out of room a little past 0.6. In dark the surface is
/// already near black and the fill holds about 6:1 at any value.
void main() {
  ThemeData themeFor(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: const Color(0xFF8560E0),
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ),
  );

  /// What the learner actually sees behind the buttons: black at
  /// [ThemeData.scrimOpacity] composited over the screen it covers.
  Color scrimOver(Color surface, double opacity) =>
      Color.alphaBlend(Colors.black.withValues(alpha: opacity), surface);

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final theme = themeFor(brightness);

    test('toolbar button clears 3:1 on the ${brightness.name} scrim', () {
      final scrim = scrimOver(theme.colorScheme.surface, theme.scrimOpacity);
      expect(
        contrastRatio(theme.toolbarButtonFill, scrim),
        greaterThanOrEqualTo(minGraphicRatio),
        reason:
            '${brightness.name}: ${theme.toolbarButtonFill} on $scrim at '
            'alpha ${theme.scrimOpacity}',
      );
    });
  }
}
