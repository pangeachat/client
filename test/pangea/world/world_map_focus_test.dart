import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_selection.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';

/// #7349 — a focused activity drives a distinct focus marker on its pin. The
/// marker is resolved purely from the inbound [MapFocus] (the `?activity=`
/// token), so it survives zoom/pan and auto-clears when the focus changes with
/// no extra state. This covers the resolution the render path threads through to
/// every tier (small dot / mid pin / large card).
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  Future<void> pumpDot(
    WidgetTester tester, {
    required PinTier tier,
    required bool isFocused,
    required Color primary,
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
            child: WorldMapDot(
              card: card,
              state: ActivityPinState.available,
              tier: tier,
              onTap: () {},
              pinged: false,
              isFocused: isFocused,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Whether any shape casts the selected-state glow — a boxShadow in [color]
  /// (the state hue) at the glow's blur radius, distinct from the pin's base
  /// black drop shadow (#7349). Scans DecoratedBox so it also matches the
  /// DecoratedBox a Container builds internally.
  bool hasStateGlow(WidgetTester tester, Color color) =>
      tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((b) {
        final d = b.decoration;
        return d is BoxDecoration &&
            (d.boxShadow ?? const []).any(
              (s) => s.color == color && s.blurRadius > 8,
            );
      });

  group('WorldMapController.focusedActivityIdOf (#7349)', () {
    test('an ActivityFocus resolves to its activity id', () {
      expect(
        WorldMapController.focusedActivityIdOf(const ActivityFocus('act-123')),
        'act-123',
      );
    });

    test('no focus resolves to null (the marker clears)', () {
      expect(WorldMapController.focusedActivityIdOf(null), isNull);
    });

    test('the resolved id is exactly the focused activity, not another', () {
      // The render path compares each pin id against this, so it must be the
      // focused id verbatim — a stray transform would ring the wrong pin.
      const focus = ActivityFocus('only-this-one');
      final id = WorldMapController.focusedActivityIdOf(focus);
      expect(id, 'only-this-one');
      expect(id == 'another', isFalse);
    });

    test('switching focus moves the marker to the new activity', () {
      // Focus is persistent but single: focusing a second activity clears the
      // first (the id the render path rings changes wholesale).
      expect(
        WorldMapController.focusedActivityIdOf(const ActivityFocus('a')),
        'a',
      );
      expect(
        WorldMapController.focusedActivityIdOf(const ActivityFocus('b')),
        'b',
      );
    });
  });

  group('WorldMapDot selected glow (#7349)', () {
    const primary = Color(0xFF112233);
    // The focused pin haloes in its state hue (here `available`), not the theme
    // primary — the treatment is state-coloured now, no outline.
    final glowColor = WorldMapSelection.glow(
      ActivityPinState.available.color,
    ).first.color;

    testWidgets('a focused small dot casts the state glow', (tester) async {
      await pumpDot(
        tester,
        tier: PinTier.small,
        isFocused: true,
        primary: primary,
      );
      expect(hasStateGlow(tester, glowColor), isTrue);
    });

    testWidgets('a focused mid pin casts the state glow', (tester) async {
      await pumpDot(
        tester,
        tier: PinTier.mid,
        isFocused: true,
        primary: primary,
      );
      expect(hasStateGlow(tester, glowColor), isTrue);
    });

    testWidgets('an unfocused dot casts no glow', (tester) async {
      await pumpDot(
        tester,
        tier: PinTier.small,
        isFocused: false,
        primary: primary,
      );
      expect(hasStateGlow(tester, glowColor), isFalse);
    });
  });
}
