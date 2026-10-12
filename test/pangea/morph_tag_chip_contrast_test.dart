import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/morph_analytics_list_view.dart';
import 'contrast_ratio.dart';

/// #9149 — the grammar chip's two hand-tuned values each have a floor. The
/// wash's alpha decides how much stage colour sits under the label, and the
/// locked label is dimmed toward the surface on purpose; either can be pushed
/// until the label stops clearing 4.5:1.
void main() {
  const textFloor = 4.5;

  ThemeData themeFor(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: const Color(0xFF8560E0),
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ),
    extensions: [PangeaColors.of(brightness)],
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final theme = themeFor(brightness);
    final surface = theme.colorScheme.surface;

    test('locked label clears 4.5:1 on the ${brightness.name} surface', () {
      expect(
        contrastRatio(MorphTagChip.lockedInk(theme), surface),
        greaterThanOrEqualTo(textFloor),
      );
    });

    testWidgets('label clears 4.5:1 on every ${brightness.name} stage wash', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        Theme(
          data: theme,
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      for (final level in ConstructLevelEnum.values) {
        final wash = Color.alphaBlend(
          level.color(context).withAlpha(MorphTagChip.washAlpha),
          surface,
        );
        expect(
          contrastRatio(theme.colorScheme.onSurface, wash),
          greaterThanOrEqualTo(textFloor),
          reason: '${level.name} on ${brightness.name}: $wash',
        );
      }
    });
  }
}
