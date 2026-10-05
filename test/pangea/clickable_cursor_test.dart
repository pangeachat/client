import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_participant_indicator.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';

/// Covers #8977: on a pointer device, a role card and a map pin must say they
/// are clickable. Both were silent — the role card explicitly forced
/// [SystemMouseCursors.basic] over a live tap, and no pin set a cursor at all —
/// so the only affordance was tapping and seeing what happened.
///
/// The negative case matters as much as the positive one: a role card with
/// nothing to open must keep the plain cursor, or the hand becomes noise.
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  /// The cursor the mouse resolves to while resting on [child]'s centre.
  Future<MouseCursor?> cursorOver(WidgetTester tester, Widget child) async {
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();

    await mouse.moveTo(tester.getCenter(find.byWidget(child)));
    await tester.pumpAndSettle();

    return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
  }

  group('role cards (#8977)', () {
    testWidgets('a selectable role card shows the click cursor', (
      tester,
    ) async {
      expect(
        await cursorOver(
          tester,
          ActivityParticipantIndicator(name: 'Chef', onTap: () {}),
        ),
        SystemMouseCursors.click,
      );
    });

    testWidgets('a role card with nothing to open keeps the plain cursor', (
      tester,
    ) async {
      expect(
        await cursorOver(
          tester,
          // No onTap and no user to open a profile popup for.
          const ActivityParticipantIndicator(name: 'Chef'),
        ),
        SystemMouseCursors.basic,
      );
    });
  });

  group('map pins (#8977)', () {
    for (final tier in [PinTier.small, PinTier.mid]) {
      for (final state in ActivityPinState.values) {
        testWidgets('a ${tier.name} ${state.name} pin shows the click cursor', (
          tester,
        ) async {
          expect(
            await cursorOver(
              tester,
              WorldMapDot(
                card: card,
                state: state,
                tier: tier,
                onTap: () {},
                pinged: false,
              ),
            ),
            SystemMouseCursors.click,
          );
        });
      }
    }

    testWidgets('a dying pin does NOT — it is on its way out and inert', (
      tester,
    ) async {
      expect(
        await cursorOver(
          tester,
          WorldMapDot(
            card: card,
            state: ActivityPinState.available,
            tier: PinTier.mid,
            onTap: () {},
            pinged: false,
            dying: true,
          ),
        ),
        SystemMouseCursors.basic,
      );
    });

    testWidgets('a large card shows the click cursor', (tester) async {
      expect(
        await cursorOver(
          tester,
          WorldMapLargeCard(
            card: card,
            state: ActivityPinState.available,
            pinged: false,
            starsEarned: 0,
            participants: const [],
            plan: null,
            openSlots: 2,
            onTap: () {},
          ),
        ),
        SystemMouseCursors.click,
      );
    });
  });
}
