import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat_list/unread_bubble.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';

/// Covers #8136: flutter_map's MarkerLayer culls/reorders its (unkeyed)
/// Positioned children every camera frame, so a [WorldMapDot]'s State can be
/// discarded and recreated mid-gesture. A recreated pin must not replay its
/// entry pop-in (`animateIn: false` renders settled immediately), a dying pin
/// built fresh must actually play its exit and fire `onExited` (or it leaks
/// into the view's `_exiting` map forever), and a mid pin with no unread room
/// must not mount an [UnreadBubble] at all.
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
    // The async L10n delegate leaves the home empty on the very first frame;
    // one zero-duration pump builds the dot without advancing the clock, so
    // assertions below still see the animation's first frame.
    await tester.pump(Duration.zero);
  }

  /// The dot's own entry/exit ScaleTransition — the outermost one in its
  /// subtree (`_WorldMapDotState.build`).
  double scaleOf(WidgetTester tester) => tester
      .widget<ScaleTransition>(
        find
            .descendant(
              of: find.byType(WorldMapDot),
              matching: find.byType(ScaleTransition),
            )
            .first,
      )
      .scale
      .value;

  group('WorldMapDot entry animation (#8136)', () {
    testWidgets('animateIn: false renders at full scale on the first frame', (
      tester,
    ) async {
      await pump(
        tester,
        const WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: PinTier.mid,
          onTap: _noop,
          pinged: false,
          animateIn: false,
        ),
      );

      // First frame only — no settle. A recreated pin must never show a
      // transient sub-scale frame.
      expect(
        scaleOf(tester),
        1.0,
        reason:
            'a pin recreated mid-gesture (animateIn: false) must render '
            'settled immediately, not replay its pop-in (#8136)',
      );
    });

    testWidgets('animateIn: true (default) plays the 0→1 scale-in', (
      tester,
    ) async {
      await pump(
        tester,
        const WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: PinTier.mid,
          onTap: _noop,
          pinged: false,
        ),
      );

      expect(
        scaleOf(tester),
        lessThan(1.0),
        reason: 'a genuinely new pin still animates in from 0',
      );

      await tester.pumpAndSettle();
      expect(scaleOf(tester), 1.0);
    });

    testWidgets('dying at construction plays the exit and fires onExited', (
      tester,
    ) async {
      // ExitingMarkersLayer builds dying dots FRESH, so didUpdateWidget's
      // false→true arm never runs — before #8136 the controller stayed at 0
      // and onExited never fired, leaking the pin into _exiting forever.
      var exited = false;
      await pump(
        tester,
        WorldMapDot(
          card: card,
          state: ActivityPinState.available,
          tier: PinTier.mid,
          onTap: _noop,
          pinged: false,
          dying: true,
          onExited: () => exited = true,
        ),
      );

      // The exit starts from full scale (the pin was visible when it died).
      expect(scaleOf(tester), 1.0);

      await tester.pumpAndSettle();
      expect(
        exited,
        isTrue,
        reason:
            'a freshly built dying dot must complete its shrink-out and '
            'call onExited so the view can drain _exiting (#8136)',
      );
      expect(scaleOf(tester), 0.0);
    });
  });

  testWidgets('a mid pin with no unread room mounts no UnreadBubble', (
    tester,
  ) async {
    await pump(
      tester,
      const WorldMapDot(
        card: card,
        state: ActivityPinState.ongoingActive,
        tier: PinTier.mid,
        onTap: _noop,
        pinged: false,
        // unreadRoom omitted (null): the badge slot must stay empty.
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(UnreadBubble),
      findsNothing,
      reason:
          'an ongoing pin whose chat has nothing unread must not show an '
          'unread badge at any point (#8136)',
    );
  });
}

void _noop() {}
