import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';

/// Covers #7920: on the map, a tap must open exactly the activity the user
/// sees — a mid pin absorbs taps only within its visible teardrop silhouette,
/// not the transparent corners of its bounding box (so an overlapping neighbour
/// can't steal the tap through empty space).
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('mid-pin glyph-accurate hit-testing (#7920)', () {
    testWidgets('a tap in the transparent box corner does NOT open the '
        'activity', (tester) async {
      var tapped = false;
      await pump(
        tester,
        WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: PinTier.mid,
          onTap: () => tapped = true,
          pinged: false,
        ),
      );

      // The mid box is midDiameter wide × (midDiameter + midPointHeight) tall;
      // its top-left corner is well outside the head circle (centre at
      // (midDiameter/2, midDiameter/2), radius midDiameter/2).
      final topLeft = tester.getTopLeft(find.byType(WorldMapDot));
      await tester.tapAt(topLeft + const Offset(2, 2));
      await tester.pump();

      expect(
        tapped,
        isFalse,
        reason:
            'a tap on the pin box\'s transparent corner must fall through, not '
            'open the activity — the corner belongs to whatever is beneath (#7920)',
      );
    });

    testWidgets('a tap on the pin head DOES open the activity', (tester) async {
      var tapped = false;
      await pump(
        tester,
        WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: PinTier.mid,
          onTap: () => tapped = true,
          pinged: false,
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(WorldMapDot));
      const headCentre = Offset(
        PinSize.midDiameter / 2,
        PinSize.midDiameter / 2,
      );
      await tester.tapAt(topLeft + headCentre);
      await tester.pump();

      expect(
        tapped,
        isTrue,
        reason: 'a tap on the visible pin head must open its activity',
      );
    });
  });

}
