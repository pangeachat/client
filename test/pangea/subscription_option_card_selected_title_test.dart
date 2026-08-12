import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_option_card.dart';

/// Covers #8303: a selected plan card wears gold on its title bar, but its
/// title ink was pinned to `onPrimaryContainer` — near-white in the dark
/// theme, so "Most popular" all but vanished on the gold. The ink now follows
/// the frame in both themes; the unselected card is untouched.
void main() {
  const plan = ProductPlan(
    planId: 'month',
    amount: 999,
    currency: 'usd',
    interval: 'month',
    intervalCount: 1,
  );

  // Seeded the way FluffyThemes.buildTheme seeds the real app, so the scheme
  // roles under test are the ones the app actually resolves.
  ThemeData themeFor(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: AppConfig.primaryColor,
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    required Brightness brightness,
    required bool selected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: themeFor(brightness),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160.0,
              child: SubscriptionOptionCard(
                plan,
                onTap: _noop,
                selected: selected,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FrameContainer frame(WidgetTester tester) =>
      tester.widget<FrameContainer>(find.byType(FrameContainer));

  /// The colour the title bar actually paints its text in.
  Color titleInk(WidgetTester tester) {
    final container = frame(tester);
    return container.titleStyle!.color ?? container.foregroundColor;
  }

  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      testWidgets('the selected card\'s title stays readable on gold', (
        tester,
      ) async {
        await pump(tester, brightness: brightness, selected: true);

        final ink = titleInk(tester);
        expect(
          ink,
          AppConfig.onGoldByTheme(
            tester.element(find.byType(SubscriptionOptionCard)),
          ),
          reason:
              'the selected title bar is gold, so its ink is the shared '
              'on-gold tone rather than a colour of its own',
        );
        expect(
          _contrast(ink, frame(tester).frameColor),
          greaterThan(4.5),
          reason: 'WCAG AA for the title against the gold it sits on',
        );
      });

      testWidgets('the unselected card is untouched', (tester) async {
        await pump(tester, brightness: brightness, selected: false);

        final scheme = themeFor(brightness).colorScheme;
        expect(
          titleInk(tester),
          scheme.onPrimaryContainer,
          reason: '#8303 is scoped to the selected card',
        );
        expect(frame(tester).frameColor, scheme.primaryContainer);
      });
    });
  }
}

/// WCAG relative-contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void _noop() {}
