import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_rating_meter.dart';
import 'contrast_ratio.dart';

/// Render contract of the activity header's rating indicator (#8088): the
/// aggregate reads as a thumbs-up share — a thumb icon plus the percentage —
/// never a ring, so an all-negative activity shows "0%" rather than an empty
/// progress dial. An unrated activity still shows the NEW pill instead.
void main() {
  Future<void> pumpMeter(
    WidgetTester tester, {
    double? average,
    int? count,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: theme,
        home: Scaffold(
          body: ActivityRatingMeter(average: average, count: count),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('all-negative reads as a thumbs up at 0%', (tester) async {
    await pumpMeter(tester, average: 0.0, count: 1);

    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('one down and one up reads 50%', (tester) async {
    await pumpMeter(tester, average: 0.5, count: 2);

    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('all-positive reads 100%', (tester) async {
    await pumpMeter(tester, average: 1.0, count: 3);

    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('an unrated activity shows the NEW pill, no thumb', (
    tester,
  ) async {
    await pumpMeter(tester, average: null, count: 0);

    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  /// Seeded the way `FluffyThemes.buildTheme` seeds the app, so the tones are
  /// the ones a learner sees. The pill's ink is lerped along with its fill, so
  /// the ratio is checked across the range, not only at the ends (#9174: 50%
  /// measured 1.3:1).
  ThemeData themeFor(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: Color(AppSettings.colorSchemeSeedInt.defaultValue),
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ),
  );

  for (final brightness in Brightness.values) {
    testWidgets('the percentage clears 4.5:1 at every rating in '
        '${brightness.name}', (tester) async {
      for (final average in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        await pumpMeter(
          tester,
          average: average,
          count: 4,
          theme: themeFor(brightness),
        );

        final pill = tester.widget<Container>(
          find.descendant(
            of: find.byType(ActivityRatingMeter),
            matching: find.byType(Container),
          ),
        );
        final fill = (pill.decoration! as BoxDecoration).color!;
        final text = tester.widget<Text>(find.textContaining('%'));
        final icon = tester.widget<Icon>(find.byIcon(Icons.thumb_up_outlined));

        for (final ink in [text.style!.color!, icon.color!]) {
          expect(
            contrastRatio(ink, fill),
            greaterThanOrEqualTo(4.5),
            reason: '${brightness.name} at $average: $ink on $fill',
          );
        }
      }
    });
  }
}
