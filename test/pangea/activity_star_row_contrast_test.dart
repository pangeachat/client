import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/goal_diamond.dart';
import 'contrast_ratio.dart';

/// The goal row is a graphic the user has to read: the count of filled vs
/// open diamonds *is* the content (#8760).
void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('goal row clears $minGraphicRatio:1 in ${brightness.name}', (
      tester,
    ) async {
      final scheme = ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: const Color(0xFF8560E0),
      );
      final theme = ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: scheme,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: theme,
          home: const Scaffold(
            body: ActivityStarRow(total: 4, earned: 3, iconSize: 22.0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final diamonds = tester
          .widgetList<GoalDiamond>(find.byType(GoalDiamond))
          .toList(growable: false);
      expect(diamonds.map((d) => d.earned), [true, true, true, false]);

      final resolved = Theme.of(tester.element(find.byType(ActivityStarRow)));
      final earned = diamonds.first.edgeIn(resolved);
      final open = diamonds.last.edgeIn(resolved);

      // The row sits on bare surfaces and inside cards; the card is the
      // tighter of the two in both themes, so both are asserted.
      for (final background in [
        scheme.surface,
        scheme.surfaceContainerHighest,
      ]) {
        expect(
          contrastRatio(earned, background),
          greaterThanOrEqualTo(minGraphicRatio),
          reason: 'earned diamond on $background in ${brightness.name}',
        );
        expect(
          contrastRatio(open, background),
          greaterThanOrEqualTo(minGraphicRatio),
          reason: 'open diamond on $background in ${brightness.name}',
        );
      }
    });
  }
}
