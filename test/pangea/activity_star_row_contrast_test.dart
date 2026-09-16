import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'contrast_ratio.dart';

/// The star row is a graphic the user has to read: the count of filled vs
/// unfilled stars *is* the content (#8760).
void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('star row clears $minGraphicRatio:1 in ${brightness.name}', (
      tester,
    ) async {
      final scheme = ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: const Color(0xFF8560E0),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            brightness: brightness,
            colorScheme: scheme,
          ),
          home: const Scaffold(
            body: ActivityStarRow(total: 4, earned: 3, iconSize: 22.0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icons = tester
          .widgetList<Icon>(find.byType(Icon))
          .toList(growable: false);
      expect(icons.length, 4);

      final earned = icons.first.color!;
      final unearned = icons.last.color!;
      expect(icons.first.icon, Icons.star);
      expect(icons.last.icon, Icons.star_border);

      // The row sits on bare surfaces and inside cards; the card is the
      // tighter of the two in both themes, so both are asserted.
      for (final background in [
        scheme.surface,
        scheme.surfaceContainerHighest,
      ]) {
        expect(
          contrastRatio(earned, background),
          greaterThanOrEqualTo(minGraphicRatio),
          reason: 'earned star on $background in ${brightness.name}',
        );
        expect(
          contrastRatio(unearned, background),
          greaterThanOrEqualTo(minGraphicRatio),
          reason: 'unearned star on $background in ${brightness.name}',
        );
      }
    });
  }

  // On a saturated state fill (an ongoing activity card) the stars take the
  // fill's ink: the earned star solid, the unearned an outline, both in the
  // ink — the gold mark is tuned for surfaces and reads muddy on a vivid fill.
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'on a state fill both stars take the fill\'s ink in ${brightness.name}',
      (tester) async {
        final scheme = ColorScheme.fromSeed(
          brightness: brightness,
          seedColor: const Color(0xFF8560E0),
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: ThemeData(
              useMaterial3: true,
              brightness: brightness,
              colorScheme: scheme,
            ),
            home: Scaffold(
              body: ColoredBox(
                color: scheme.primaryContainer,
                child: ActivityStarRow(
                  total: 4,
                  earned: 3,
                  iconSize: 22.0,
                  earnedColor: scheme.onPrimaryContainer,
                  emptyColor: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final icons = tester
            .widgetList<Icon>(find.byType(Icon))
            .toList(growable: false);
        expect(icons.first.icon, Icons.star);
        expect(icons.last.icon, Icons.star_border);
        for (final icon in icons) {
          expect(icon.color, scheme.onPrimaryContainer);
          expect(
            contrastRatio(icon.color!, scheme.primaryContainer),
            greaterThanOrEqualTo(minGraphicRatio),
            reason:
                'star in the fill\'s ink on primaryContainer, '
                '${brightness.name}',
          );
        }
      },
    );
  }
}
