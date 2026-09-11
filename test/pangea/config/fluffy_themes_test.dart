import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/config/themes.dart';

void main() {
  const seed = Color(0xFF8560E0);

  Future<ThemeData> builtTheme(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    late ThemeData theme;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Theme(
            data: FluffyThemes.buildTheme(context, brightness, seed),
            child: Builder(
              builder: (inner) {
                theme = Theme.of(inner);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return theme;
  }

  testWidgets('the scheme keeps the seed chroma (fidelity variant)', (
    tester,
  ) async {
    final theme = await builtTheme(tester, Brightness.light);
    final fidelity = ColorScheme.fromSeed(
      seedColor: seed,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    expect(theme.colorScheme.primary, fidelity.primary);
    expect(theme.colorScheme.primaryContainer, fidelity.primaryContainer);
  });

  testWidgets('the theme carries the brand roles for its brightness', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = await builtTheme(tester, brightness);
      final expected = PangeaColors.of(brightness);
      expect(theme.extension<PangeaColors>(), isNotNull);
      expect(theme.pangea.gold, expected.gold);
      expect(theme.pangea.goldFixedDim, expected.goldFixedDim);
    }
  });

  testWidgets('the AppConfig gold helpers read the theme roles', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Theme(
            data: FluffyThemes.buildTheme(context, Brightness.light, seed),
            child: Builder(
              builder: (inner) {
                captured = inner;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    final roles = PangeaColors.of(Brightness.light);
    expect(AppConfig.goldByTheme(captured), roles.goldFixedDim);
    expect(AppConfig.onGoldByTheme(captured), roles.onGoldFixed);
    expect(AppConfig.goldMarkByTheme(captured), roles.goldGraphic);
    expect(AppConfig.warningByTheme(captured), roles.warningGraphic);
  });
}
