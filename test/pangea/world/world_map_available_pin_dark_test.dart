import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_pin_shape.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';

/// Covers #8174: the `available` pin's light-brand fill is near-white, which
/// over the dark theme's near-black basemap made the map's LEAST urgent state
/// its loudest mark. In the dark theme it fills darker instead — while every
/// other state, and the whole light theme, are untouched, and the white plus
/// glyph stays white (the fill is dark enough to carry it).
void main() {
  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Test Activity',
    l2: 'es',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  Future<void> pump(
    WidgetTester tester, {
    required Brightness brightness,
    required ActivityPinState state,
    required PinTier tier,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Center(
            child: WorldMapDot(
              card: card,
              state: state,
              tier: tier,
              onTap: _noop,
              pinged: false,
              animateIn: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The mid pin's teardrop body fill.
  Color midFill(WidgetTester tester) =>
      (tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is TeardropPainter,
                    ),
                  )
                  .painter!
              as TeardropPainter)
          .color;

  /// The small pin's circular body fill.
  Color smallFill(WidgetTester tester) {
    final container = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(WorldMapDot),
            matching: find.byType(Container),
          ),
        )
        .firstWhere(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).shape == BoxShape.circle,
        );
    return (container.decoration! as BoxDecoration).color!;
  }

  group('available pin fill by theme (#8174)', () {
    testWidgets('light theme keeps the light brand fill (mid + small)', (
      tester,
    ) async {
      await pump(
        tester,
        brightness: Brightness.light,
        state: ActivityPinState.available,
        tier: PinTier.mid,
      );
      expect(midFill(tester), AppConfig.primaryColorLight);

      await pump(
        tester,
        brightness: Brightness.light,
        state: ActivityPinState.available,
        tier: PinTier.small,
      );
      expect(
        smallFill(tester),
        AppConfig.primaryColorLight,
        reason: 'the light theme is unchanged by #8174',
      );
    });

    testWidgets('dark theme darkens the fill (mid + small)', (tester) async {
      await pump(
        tester,
        brightness: Brightness.dark,
        state: ActivityPinState.available,
        tier: PinTier.mid,
      );
      final mid = midFill(tester);

      await pump(
        tester,
        brightness: Brightness.dark,
        state: ActivityPinState.available,
        tier: PinTier.small,
      );
      final small = smallFill(tester);

      expect(
        small,
        mid,
        reason: 'both tiers share one available fill, whatever the theme',
      );
      expect(
        mid,
        isNot(AppConfig.primaryColorLight),
        reason: 'the near-white light-brand fill is what #8174 replaced',
      );
      expect(
        mid,
        isNot(AppConfig.primaryColor),
        reason:
            'it must not become the Ongoing purple — the states have to stay '
            'tellable apart',
      );
      expect(
        mid.computeLuminance(),
        lessThan(AppConfig.primaryColor.computeLuminance()),
        reason:
            'darker than the Ongoing purple, so it reads as the quiet state '
            'rather than a variant of the live one',
      );
      expect(
        _contrast(mid, Colors.white),
        greaterThan(4.5),
        reason: 'the white plus glyph must stay legible on the new fill',
      );
    });

    testWidgets('the plus glyph stays white in the dark theme', (tester) async {
      await pump(
        tester,
        brightness: Brightness.dark,
        state: ActivityPinState.available,
        tier: PinTier.mid,
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.add));
      expect(
        icon.color,
        Colors.white,
        reason:
            '#8174 darkened the fill rather than darkening the glyph — the '
            'plus stays white on every state pin',
      );
    });

    testWidgets('live states are identical in both themes', (tester) async {
      for (final state in [
        ActivityPinState.joinable,
        ActivityPinState.ongoingActive,
      ]) {
        await pump(
          tester,
          brightness: Brightness.light,
          state: state,
          tier: PinTier.mid,
        );
        final light = midFill(tester);

        await pump(
          tester,
          brightness: Brightness.dark,
          state: state,
          tier: PinTier.mid,
        );

        expect(
          midFill(tester),
          light,
          reason:
              '#8174 is scoped to the available pin; $state must look the '
              'same in both themes',
        );
      }
    });
  });
}

/// WCAG relative-contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void _noop() {}
