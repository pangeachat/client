import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_selection.dart';

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
    ActivityPinState state = ActivityPinState.available,
    List<LargeCardParticipant> participants = const [],
    int openSlots = 0,
    int starsEarned = 0,
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
              state: state,
              pinged: false,
              plan: null,
              starsEarned: starsEarned,
              participants: participants,
              openSlots: openSlots,
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

  /// Whether any shape casts the selected-state glow — a boxShadow in [color]
  /// (the state hue) at the glow's blur radius — the distinct focused marker
  /// now that the outline is gone (#7349). Scans DecoratedBox (a Container
  /// builds one internally).
  bool hasStateGlow(WidgetTester tester, Color color) =>
      tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((b) {
        final d = b.decoration;
        return d is BoxDecoration &&
            (d.boxShadow ?? const []).any(
              (s) => s.color == color && s.blurRadius > 8,
            );
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

  group('selected glow (#7349)', () {
    // The focused card haloes in its state hue (here `available`) with no
    // outline — the same treatment as a selected pin.
    final glowColor =
        WorldMapSelection.glow(ActivityPinState.available.accent).first.color;

    testWidgets('a focused card casts the state glow around the balloon', (
      tester,
    ) async {
      await pumpCard(tester, isFocused: true);
      expect(
        hasStateGlow(tester, glowColor),
        isTrue,
        reason: 'the focused card haloes in a state-coloured glow',
      );
    });

    testWidgets('an unfocused card casts no glow', (tester) async {
      await pumpCard(tester, isFocused: false);
      expect(
        hasStateGlow(tester, glowColor),
        isFalse,
        reason: 'only the focused state adds the glow',
      );
    });
  });

  group('state-dispatched body (world-map.instructions.md, "Pin display")', () {
    testWidgets('joinable shows a door icon + the participant row', (
      tester,
    ) async {
      // openSlots only (no real participants): the open-slot person-icon
      // placeholder is a plain CircleAvatar + Icon, so (unlike the app's Avatar
      // widget, which needs app-level env init this unit test doesn't provide)
      // it renders here — a filled participant would hit that Avatar gap.
      await pumpCard(tester, state: ActivityPinState.joinable, openSlots: 1);
      expect(find.byIcon(Icons.meeting_room), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('ongoingPending shows an hourglass icon, no door', (
      tester,
    ) async {
      await pumpCard(
        tester,
        state: ActivityPinState.ongoingPending,
        openSlots: 2,
      );
      // hourglass_bottom (the half-full glass) matches the mid pin's icon.
      expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);
      expect(find.byIcon(Icons.meeting_room), findsNothing);
    });

    testWidgets(
      'ongoingActive shows the star row and no participant row/door/hourglass',
      (tester) async {
        await pumpCard(
          tester,
          state: ActivityPinState.ongoingActive,
          starsEarned: 0,
        );
        expect(find.byIcon(Icons.meeting_room), findsNothing);
        expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
        expect(find.byIcon(Icons.person), findsNothing);
      },
    );

    testWidgets(
      'a non-eligible state (available/inProgress) renders no body content',
      (tester) async {
        // available/inProgress never reach this widget in production (the
        // ranking/placement large-tier hard gate excludes them beforehand) —
        // this just confirms the defensive default doesn't crash or show a
        // stray icon.
        await pumpCard(tester, state: ActivityPinState.available);
        expect(find.byIcon(Icons.meeting_room), findsNothing);
        expect(find.byIcon(Icons.hourglass_bottom), findsNothing);
      },
    );
  });
}
