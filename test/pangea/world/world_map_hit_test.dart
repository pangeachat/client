import 'package:flutter/gestures.dart';
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
///
/// And #8591: the hovered pin's title label must take no pointer input at all,
/// so the map underneath keeps zooming and the pin keeps taking clicks.
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

  group('a hovered pin label takes no pointer input (#8591)', () {
    /// The pin over a full-screen stand-in for the map, hovered so its title
    /// label is showing. Returns the label's centre.
    Future<Offset> hoverPin(
      WidgetTester tester, {
      VoidCallback? onMapTap,
      void Function(PointerSignalEvent)? onMapPointerSignal,
    }) async {
      await pump(
        tester,
        Stack(
          children: [
            Listener(
              onPointerSignal: onMapPointerSignal,
              behavior: HitTestBehavior.opaque,
              child: GestureDetector(
                onTap: onMapTap,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            Center(
              child: WorldMapDot(
                card: card,
                state: ActivityPinState.available,
                tier: PinTier.mid,
                onTap: () {},
                pinged: false,
              ),
            ),
          ],
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(WorldMapDot)));
      await tester.pumpAndSettle();

      expect(
        find.text(card.title),
        findsOneWidget,
        reason: 'hovering a pin still shows its title',
      );
      return tester.getCenter(find.text(card.title));
    }

    testWidgets('a tap on the label reaches the map beneath', (tester) async {
      var mapTapped = false;
      final label = await hoverPin(tester, onMapTap: () => mapTapped = true);

      await tester.tapAt(label);
      await tester.pump();

      expect(
        mapTapped,
        isTrue,
        reason:
            'the label must not swallow taps - a click on it belongs to '
            'whatever it is covering (#8591)',
      );
    });

    testWidgets('a scroll over the label reaches the map beneath', (
      tester,
    ) async {
      var scrolls = 0;
      final label = await hoverPin(
        tester,
        onMapPointerSignal: (_) => scrolls++,
      );

      final pointer = TestPointer(2, PointerDeviceKind.mouse);
      pointer.hover(label);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();

      expect(
        scrolls,
        1,
        reason:
            'zooming must survive the label drifting under the cursor - the '
            'map, not the label, owns the scroll (#8591)',
      );
    });
  });
}
