import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';

/// Covers #7688: a small-tier dot is painted deliberately tiny
/// ([PinSize.smallDiameter]), which made it near-impossible to tap on a phone
/// without zooming in until it earned a mid pin. Its marker box — and so its
/// hit target — is padded out to [PinSize.dotTouchTarget] (Material's minimum
/// interactive dimension), centred on the same anchor, while the painted dot
/// keeps its size. A mid teardrop is unaffected (its silhouette-only hit-test
/// from #7920 stays), and a dying dot's enlarged box must not shadow the live
/// pins beneath it.
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  /// Pumps [dot] the way flutter_map's MarkerLayer does — a tight box of the
  /// tier's marker size — so the widget under test sees real map constraints.
  /// With [settle] false, only the first built frame is pumped (the async L10n
  /// delegate leaves the first frame empty), so a dying pin is caught at the
  /// start of its exit rather than already scaled to nothing.
  Future<void> pumpInMarkerBox(
    WidgetTester tester,
    WorldMapDot dot, {
    Widget? beneath,
    bool settle = true,
  }) async {
    final box = dot.tier.markerBox(dot.state);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                ?beneath,
                SizedBox.fromSize(size: box, child: dot),
              ],
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(Duration.zero);
    }
  }

  group('PinTier.markerBox', () {
    test('a small dot takes the min touch-target box in every state', () {
      for (final state in ActivityPinState.values) {
        expect(
          PinTier.small.markerBox(state),
          const Size.square(PinSize.dotTouchTarget),
          reason: 'small/${state.name} must pad out to the touch target',
        );
      }
      expect(
        PinSize.dotTouchTarget,
        greaterThanOrEqualTo(kMinInteractiveDimension),
        reason: 'the target must meet Material\'s minimum interactive size',
      );
    });

    test('the completed trail star is a dot at any tier', () {
      expect(
        PinTier.mid.markerBox(ActivityPinState.inProgress),
        const Size.square(PinSize.dotTouchTarget),
      );
    });

    test('a mid teardrop keeps its own head+point box', () {
      expect(
        PinTier.mid.markerBox(ActivityPinState.available),
        const Size(
          PinSize.midDiameter,
          PinSize.midDiameter + PinSize.midPointHeight,
        ),
      );
    });
  });

  group('small dot tap target (#7688)', () {
    testWidgets('a tap well outside the painted dot but inside its touch '
        'target opens the activity', (tester) async {
      var tapped = false;
      await pumpInMarkerBox(
        tester,
        WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: PinTier.small,
          onTap: () => tapped = true,
          pinged: false,
        ),
      );

      // Just inside the box's top-left corner: (2, 2) from the corner is
      // dotTouchTarget/2 - 2 = 22 px from the dot's centre — far past the
      // 4 px painted radius, but within the touch target.
      final topLeft = tester.getTopLeft(find.byType(WorldMapDot));
      await tester.tapAt(topLeft + const Offset(2, 2));
      await tester.pump();

      expect(
        tapped,
        isTrue,
        reason:
            'the whole touch-target box must open the activity, not just the '
            'tiny painted dot (#7688)',
      );
    });

    testWidgets('the painted dot keeps its small diameter, centred on the '
        'anchor', (tester) async {
      await pumpInMarkerBox(
        tester,
        const WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: PinTier.small,
          onTap: _noop,
          pinged: false,
        ),
      );

      final dotFinder = find.byType(WorldMapDot);
      final painted = find.descendant(
        of: dotFinder,
        matching: find.byType(DecoratedBox),
      );
      expect(painted, findsOneWidget);
      expect(
        tester.getSize(painted),
        const Size.square(PinSize.smallDiameter),
        reason: 'only the hit target grows — the dot stays a small dot',
      );
      expect(
        tester.getCenter(painted),
        tester.getCenter(dotFinder),
        reason: 'the dot must stay centred on its geographic anchor',
      );
      expect(
        tester.getSize(dotFinder),
        const Size.square(PinSize.dotTouchTarget),
      );
    });

    testWidgets('a dying dot\'s box lets taps through to what is beneath', (
      tester,
    ) async {
      var beneathTapped = false;
      await pumpInMarkerBox(
        tester,
        const WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: PinTier.small,
          onTap: _noop,
          pinged: false,
          dying: true,
          onExited: _noop,
        ),
        beneath: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => beneathTapped = true,
          child: const SizedBox.square(dimension: PinSize.dotTouchTarget),
        ),
        // First frame of the exit: the pin is still at full scale, so its box
        // is exactly where a live pin's would be.
        settle: false,
      );

      await tester.tapAt(tester.getCenter(find.byType(WorldMapDot)));
      await tester.pump();

      expect(
        beneathTapped,
        isTrue,
        reason:
            'an exiting pin is inert; its enlarged box must not shadow the '
            'live pins under the exiting layer',
      );
      // Let the exit finish so the animation controller isn't left ticking.
      await tester.pumpAndSettle();
    });
  });

  group('mid pin unaffected', () {
    testWidgets('a tap in the transparent box corner still falls through '
        '(#7920)', (tester) async {
      var tapped = false;
      await pumpInMarkerBox(
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
      await tester.tapAt(topLeft + const Offset(2, 2));
      await tester.pump();

      expect(tapped, isFalse);
    });
  });
}

void _noop() {}
