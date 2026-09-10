import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

/// Covers #8880 (second half of #8689 item 5): the world map's zoom controls
/// and the cluster's stat trackers showed focus only through Material's own
/// state-layer wash — 1.17:1 to 1.45:1, against the 3:1 WCAG 1.4.11 asks of a
/// focus indicator. Both now wear the app's one gold ring, and that gold is
/// [AppConfig.goldMarkByTheme] rather than the decorative gold, which was
/// itself under 3:1 in light mode (#8760).
void main() {
  // Rings render only in traditional (keyboard) highlight mode; the test
  // binding's platform defaults to touch, so pin the mode. The touch-gate
  // tests override it per-test.
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDownAll(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  /// The WCAG 2.1 contrast ratio between two opaque colors.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  group('the ring colour clears 1.4.11 in both themes', () {
    // The surfaces the two new ring sites actually sit on: the zoom stack is a
    // Material in `surface`, the trackers sit on the pill's inner
    // `surfaceContainer` field.
    ColorScheme schemeOf(Brightness brightness) => ColorScheme.fromSeed(
      seedColor: const Color(0xFF8560E0),
      brightness: brightness,
    );

    test('light — the deepened gold, not the decorative one', () {
      final scheme = schemeOf(Brightness.light);
      expect(
        contrast(AppConfig.goldDeep, scheme.surface),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrast(AppConfig.goldDeep, scheme.surfaceContainer),
        greaterThanOrEqualTo(3.0),
        reason: 'the trackers sit on surfaceContainer',
      );
      // The failure this fixes: the decorative gold on the same two surfaces.
      expect(contrast(AppConfig.gold, scheme.surface), lessThan(3.0));
      expect(contrast(AppConfig.gold, scheme.surfaceContainer), lessThan(3.0));
    });

    test('dark — the decorative gold already clears, and deep would not', () {
      final scheme = schemeOf(Brightness.dark);
      expect(
        contrast(AppConfig.gold, scheme.surface),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrast(AppConfig.gold, scheme.surfaceContainer),
        greaterThanOrEqualTo(3.0),
      );
      // Why the colour is theme-aware rather than one deepened gold serving
      // both: [goldDeep] falls under 3:1 on the darkest card, which is where
      // [AppConfig.goldMarkByTheme]'s other consumer — the activity star row
      // — has to hold up (#8760).
      expect(
        contrast(AppConfig.goldDeep, scheme.surfaceContainerHighest),
        lessThan(3.0),
      );
    });
  });

  group(
    'a control that is already a button takes the ring through its style',
    () {
      testWidgets('the ring appears on Tab and clears when focus leaves', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Zoom in',
                      style: ButtonStyle(
                        side: FocusRingTapTarget.ringSideProperty(context),
                      ),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      tooltip: 'Zoom out',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        BorderSide sideOn(IconData icon) {
          final material = tester.widget<Material>(
            find
                .ancestor(
                  of: find.byIcon(icon),
                  matching: find.byType(Material),
                )
                .first,
          );
          return (material.shape! as OutlinedBorder).side;
        }

        expect(sideOn(Icons.add).style, BorderStyle.none);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          sideOn(Icons.add).width,
          FocusRingTapTarget.ringWidth,
          reason:
              'Tab must put the gold ring on the zoom button; focus is on '
              '${FocusManager.instance.primaryFocus}',
        );
        expect(
          sideOn(Icons.add).color,
          AppConfig.goldDeep,
          reason:
              'the light ring is the deepened gold — the decorative one is '
              'under 3:1 on the map surface (#8760, #8880)',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          sideOn(Icons.add).style,
          BorderStyle.none,
          reason: 'the ring must follow focus off the button',
        );
      });

      testWidgets('no ring in touch highlight mode', (tester) async {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Zoom in',
                  style: ButtonStyle(
                    side: FocusRingTapTarget.ringSideProperty(context),
                  ),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();

        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.byIcon(Icons.add),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          (material.shape! as OutlinedBorder).side.style,
          BorderStyle.none,
          reason:
              'focus rings are keyboard affordances; touch must not paint one',
        );
      });
    },
  );

  group('the cluster trackers', () {
    /// Whether a tracker currently paints the gold ring — the
    /// [FocusRingTapTarget.ringWidth]-side ShapeDecoration, same assertion as
    /// cluster_keyboard_focus_test: one shared ring look.
    bool showsFocusRing(WidgetTester tester, Finder root) => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: root, matching: find.byType(DecoratedBox)),
        )
        .any((box) {
          final decoration = box.decoration;
          return decoration is ShapeDecoration &&
              decoration.shape is OutlinedBorder &&
              (decoration.shape as OutlinedBorder).side.width ==
                  FocusRingTapTarget.ringWidth;
        });

    Widget trackers({bool selected = false}) => MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Column(
          children: [
            ClusterTrackerButton(
              indicator: ProgressIndicatorEnum.stars,
              count: 3,
              selected: selected,
              onTap: () {},
            ),
            ClusterTrackerButton(
              indicator: ProgressIndicatorEnum.morphsUsed,
              count: 12,
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    testWidgets('Tab rings each tracker in turn, and Enter activates', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                ClusterTrackerButton(
                  indicator: ProgressIndicatorEnum.stars,
                  count: 3,
                  onTap: () => opened++,
                ),
                ClusterTrackerButton(
                  indicator: ProgressIndicatorEnum.morphsUsed,
                  count: 12,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stars = find.byType(ClusterTrackerButton).first;
      final grammar = find.byType(ClusterTrackerButton).last;
      expect(showsFocusRing(tester, stars), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        showsFocusRing(tester, stars),
        isTrue,
        reason:
            'one Tab must ring the Stars tracker; focus is on '
            '${FocusManager.instance.primaryFocus}',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, 1, reason: 'Enter must open the tracker\'s analytics');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        showsFocusRing(tester, stars),
        isFalse,
        reason: 'the ring must follow focus off the Stars tracker',
      );
      expect(showsFocusRing(tester, grammar), isTrue);
    });

    testWidgets('the ring still shows on the tracker whose panel is open', (
      tester,
    ) async {
      // #8724 review: the open-panel wash is painted as Ink, under the
      // regular child painting — a ring painted behind the child would be
      // swallowed by it, so this is the case that pins the foreground.
      await tester.pumpWidget(trackers(selected: true));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        showsFocusRing(tester, find.byType(ClusterTrackerButton).first),
        isTrue,
        reason: 'the lit tracker must still show its ring',
      );
    });

    testWidgets('no ring in touch highlight mode', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      await tester.pumpWidget(trackers());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        showsFocusRing(tester, find.byType(ClusterTrackerButton).first),
        isFalse,
        reason:
            'focus rings are keyboard affordances; touch must not paint one',
      );
    });
  });
}
