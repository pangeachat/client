import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/level_up_badge_celebration.dart';

/// Coverage for [LevelUpBadgeCelebration] — the badge-anchored replacement
/// for the level-up top-down chat snackbar (#7432). The widget is plain
/// values only (a badge child + a [LevelUpdate] stream), so it's driven here
/// with a bare [StreamController], no Matrix plumbing.
void main() {
  // Test-shortened timings so each case advances past every animation and
  // timer quickly and deterministically.
  const chipDuration = Duration(milliseconds: 400);
  const pulseDuration = Duration(milliseconds: 200);
  const fadeOut = Duration(milliseconds: 300);

  const badgeKey = Key('badge');
  const badgeSize = Size(40, 44);

  Future<void> pumpCelebration(
    WidgetTester tester,
    Stream<LevelUpdate> levelUpdates,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: LevelUpBadgeCelebration(
              levelUpdates: levelUpdates,
              chipDuration: chipDuration,
              pulseDuration: pulseDuration,
              child: const SizedBox(key: badgeKey, width: 40, height: 44),
            ),
          ),
        ),
      ),
    );
    // The L10n delegates load asynchronously (same as the other navigation
    // tests).
    await tester.pumpAndSettle();
  }

  L10n l10nOf(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(Scaffold)));

  testWidgets('a level bump shows the chip with the new level text', (
    tester,
  ) async {
    final controller = StreamController<LevelUpdate>.broadcast();
    await pumpCelebration(tester, controller.stream);
    final chipText = l10nOf(tester).levelUpChip(4);

    expect(find.text(chipText), findsNothing);

    controller.add(const LevelUpdate(prevLevel: 3, newLevel: 4));
    await tester.pump(); // deliver the stream event
    await tester.pump(); // first celebration frame

    expect(find.text(chipText), findsOneWidget);
    // The badge itself is still in the tree, untouched.
    expect(find.byKey(badgeKey), findsOneWidget);

    // Let the pulse and the chip run out before the test ends.
    await tester.pump(pulseDuration);
    await tester.pump(chipDuration + fadeOut);
    await tester.pumpAndSettle();
    await controller.close();
  });

  testWidgets('the chip disappears on its own after chipDuration', (
    tester,
  ) async {
    final controller = StreamController<LevelUpdate>.broadcast();
    await pumpCelebration(tester, controller.stream);
    final chipText = l10nOf(tester).levelUpChip(2);

    controller.add(const LevelUpdate(prevLevel: 1, newLevel: 2));
    await tester.pump();
    await tester.pump();
    expect(find.text(chipText), findsOneWidget);

    // Still visible right before the timer fires.
    await tester.pump(chipDuration - const Duration(milliseconds: 50));
    expect(find.text(chipText), findsOneWidget);

    // Past the hold + fade-out: gone, with nothing pending.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(fadeOut);
    await tester.pumpAndSettle();
    expect(find.text(chipText), findsNothing);
    await controller.close();
  });

  testWidgets('no chip when the level did not increase', (tester) async {
    final controller = StreamController<LevelUpdate>.broadcast();
    await pumpCelebration(tester, controller.stream);
    final l10n = l10nOf(tester);

    controller.add(const LevelUpdate(prevLevel: 4, newLevel: 4));
    controller.add(const LevelUpdate(prevLevel: 4, newLevel: 3));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.levelUpChip(4)), findsNothing);
    expect(find.text(l10n.levelUpChip(3)), findsNothing);
    await controller.close();
  });

  testWidgets('the badge keeps its exact layout footprint while celebrating', (
    tester,
  ) async {
    final controller = StreamController<LevelUpdate>.broadcast();
    await pumpCelebration(tester, controller.stream);

    expect(tester.getSize(find.byType(LevelUpBadgeCelebration)), badgeSize);

    controller.add(const LevelUpdate(prevLevel: 3, newLevel: 4));
    await tester.pump();
    await tester.pump();

    // Pulse and chip are paint-time effects only — the celebration never
    // grows the badge's layout box (so it can't push the surfaces around).
    expect(tester.getSize(find.byType(LevelUpBadgeCelebration)), badgeSize);

    await tester.pump(pulseDuration);
    await tester.pump(chipDuration + fadeOut);
    await tester.pumpAndSettle();
    await controller.close();
  });

  testWidgets('the chip is a polite live region and intercepts no taps', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = StreamController<LevelUpdate>.broadcast();
    await pumpCelebration(tester, controller.stream);
    final chipText = l10nOf(tester).levelUpChip(5);

    controller.add(const LevelUpdate(prevLevel: 4, newLevel: 5));
    await tester.pump(); // deliver the stream event
    await tester.pump(); // anchor the animation tickers
    // Let the fade-in finish: FadeTransition contributes no semantics at
    // opacity 0, so the node only exists once the chip is actually visible.
    await tester.pump(const Duration(milliseconds: 250));

    // Announced politely (live region), not focus-stealing.
    expect(
      tester.getSemantics(find.bySemanticsLabel(chipText)),
      matchesSemantics(label: chipText, isLiveRegion: true),
    );

    // Decoration only: the chip subtree never hit-tests. The nearest
    // IgnorePointer ancestor is the celebration's own wrapper (further ones
    // belong to the framework chrome).
    final ignoring = tester
        .widgetList<IgnorePointer>(
          find.ancestor(
            of: find.text(chipText),
            matching: find.byType(IgnorePointer),
          ),
        )
        .first;
    expect(ignoring.ignoring, isTrue);

    await tester.pump(pulseDuration);
    await tester.pump(chipDuration + fadeOut);
    await tester.pumpAndSettle();
    await controller.close();
    semantics.dispose();
  });
}
