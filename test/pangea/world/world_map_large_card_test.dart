import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Covers #7207: every map large card gets a dismiss X (wired to the
/// controller's demote-to-mid dismissal) that fires **without** opening the
/// activity; a null onClose hides the X (the widget's reuse/test knob).
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    VoidCallback? onClose,
    VoidCallback? onTap,
    bool isFocused = false,
    Color primary = const Color(0xFF112233),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: primary,
          ).copyWith(primary: primary),
        ),
        home: Scaffold(
          body: Center(
            child: WorldMapLargeCard(
              card: card,
              state: ActivityPinState.available,
              pinged: false,
              plan: null,
              starsEarned: 0,
              onTap: onTap ?? () {},
              onClose: onClose,
              isFocused: isFocused,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Whether any Container draws a border in [color] (the focus ring's primary
  /// border) — the distinct focused marker (#7349).
  bool hasBorderColored(WidgetTester tester, Color color) =>
      tester.widgetList<Container>(find.byType(Container)).any((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.border is Border &&
            (d.border as Border).top.color == color;
      });

  testWidgets(
    'a selected card shows a dismiss X that fires onClose, not onTap',
    (tester) async {
      var closed = false;
      var opened = false;
      await pumpCard(
        tester,
        onClose: () => closed = true,
        onTap: () => opened = true,
      );

      final x = find.byIcon(Icons.close);
      expect(x, findsOneWidget);

      await tester.tap(x);
      await tester.pumpAndSettle();
      expect(closed, isTrue, reason: 'the X dismisses the card (onClose)');
      expect(
        opened,
        isFalse,
        reason: 'the X must not open the activity (onTap stays unfired)',
      );
    },
  );

  testWidgets('a card with no onClose (widget reuse knob) shows no dismiss X', (
    tester,
  ) async {
    await pumpCard(tester, onClose: null);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  group('focus ring (#7349)', () {
    const primary = Color(0xFF112233);

    testWidgets('a focused card draws a primary-coloured focus ring', (
      tester,
    ) async {
      await pumpCard(tester, isFocused: true, primary: primary);
      expect(
        hasBorderColored(tester, primary),
        isTrue,
        reason: 'the focused card wraps in a primary-coloured ring',
      );
    });

    testWidgets('an unfocused card has no primary focus ring', (tester) async {
      await pumpCard(tester, isFocused: false, primary: primary);
      expect(
        hasBorderColored(tester, primary),
        isFalse,
        reason: 'only the focused state adds the primary ring',
      );
    });
  });
}
