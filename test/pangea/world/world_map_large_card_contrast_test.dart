import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Covers #8968: a playtester could not read the large card's title in the dark
/// theme. The title is ink on `colorScheme.surface`, and it used to take the raw
/// `AppConfig.primaryColor` — which measures 4.20:1 over the dark surface and
/// 4.21:1 over the light one, both under WCAG 2.1 AA's 4.5:1 for the card's
/// 13px/14px type (accessibility.instructions.md targets AA).
///
/// The ratio is the requirement, so the ratio is what this asserts — a later
/// palette or theme change that quietly drops the title back under AA fails
/// here rather than at the next playtest.
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    cefr: 'a1',
    roleCount: 2,
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  /// WCAG 2.1 relative luminance (SC 1.4.3). Colours reaching here are opaque —
  /// the card paints an opaque surface under opaque text.
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
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Seeded exactly the way `FluffyThemes.buildTheme` seeds the real app, so
  /// the resolved tones are the ones a learner actually sees. No `copyWith`
  /// override here — overriding `primary` would test a colour the app never
  /// renders.
  ThemeData themeFor(Brightness brightness) => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: AppConfig.primaryColor,
    ),
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required Brightness brightness,
    required ActivityPinState state,
    required bool isFocused,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: themeFor(brightness),
        home: Scaffold(
          body: Center(
            child: WorldMapLargeCard(
              card: card,
              state: state,
              pinged: false,
              plan: null,
              starsEarned: 0,
              participants: const [],
              openSlots: 0,
              onTap: () {},
              onClose: null,
              isFocused: isFocused,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The rendered colour of the card's activity-name text.
  Color titleColor(WidgetTester tester) {
    final text = tester.widget<Text>(find.text(card.title));
    return text.style!.color!;
  }

  /// The card body paints `colorScheme.surface` behind that text.
  Color surfaceOf(Brightness brightness) =>
      themeFor(brightness).colorScheme.surface;

  // AA for text below 18.66px bold / 24px regular. The card's title is 13px
  // bold and its Available row 14px w600 — both "normal text".
  const aaNormalText = 4.5;

  // `available` is the state the playtester reported; the two Ongoing states
  // rendered the identical purple on the identical surface, so they are the
  // same defect and are covered here rather than left to reappear.
  for (final state in [
    ActivityPinState.available,
    ActivityPinState.ongoingPending,
    ActivityPinState.ongoingActive,
  ]) {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      for (final isFocused in [false, true]) {
        final name =
            '${state.name} title clears WCAG AA in the '
            '${brightness.name} theme${isFocused ? ' while focused' : ''}';

        testWidgets(name, (tester) async {
          await pumpCard(
            tester,
            brightness: brightness,
            state: state,
            isFocused: isFocused,
          );

          final ratio = contrast(titleColor(tester), surfaceOf(brightness));
          expect(
            ratio,
            greaterThanOrEqualTo(aaNormalText),
            reason:
                'the ${state.name} card title measured ${ratio.toStringAsFixed(2)}:1 '
                'against the ${brightness.name} surface; AA needs '
                '$aaNormalText:1 for 13px/14px type (#8968)',
          );
        });
      }
    }
  }

  testWidgets('the Available row inherits the title colour, so its CEFR and '
      'party-size text clear AA too', (tester) async {
    await pumpCard(
      tester,
      brightness: Brightness.dark,
      state: ActivityPinState.available,
      isFocused: false,
    );

    // The row's 14px w600 label is the same ink as the title by construction;
    // assert that rather than a second ratio, so the two can never drift apart.
    final cefr = tester.widget<Text>(find.text('A1'));
    expect(cefr.style!.color, titleColor(tester));
  });
}
