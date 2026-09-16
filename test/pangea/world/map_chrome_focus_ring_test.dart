import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import '../contrast_ratio.dart';
import '../one_node_control.dart';

/// #8880: the map's zoom controls and the cluster's stat trackers showed focus
/// only through Material's own wash (1.17:1 to 1.45:1). Both now wear the
/// app's gold focus ring.
void main() {
  setUp(() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });
  tearDownAll(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  ThemeData themeFor(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF8560E0),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ),
    extensions: [PangeaColors.of(brightness)],
  );

  for (final brightness in Brightness.values) {
    final theme = themeFor(brightness);
    final scheme = theme.colorScheme;
    final name = brightness.name;

    group('stat trackers ($name)', () {
      final tapped = <ProgressIndicatorEnum>[];

      /// The three trackers on the pill's `surfaceContainer` field, Vocab lit
      /// as if its panel were open.
      Future<void> pumpTrackers(WidgetTester tester) async {
        tapped.clear();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: Center(
                child: Container(
                  color: scheme.surfaceContainer,
                  padding: const EdgeInsets.all(4),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final indicator in [
                          ProgressIndicatorEnum.stars,
                          ProgressIndicatorEnum.morphsUsed,
                          ProgressIndicatorEnum.wordsUsed,
                        ])
                          ClusterTrackerButton(
                            indicator: indicator,
                            count: 3,
                            selected:
                                indicator == ProgressIndicatorEnum.wordsUsed,
                            onTap: () => tapped.add(indicator),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder tracker(ProgressIndicatorEnum indicator) => find.byWidgetPredicate(
        (w) => w is ClusterTrackerButton && w.indicator == indicator,
      );

      /// The ring the tracker currently paints, or null.
      BorderSide? ringOn(WidgetTester tester, ProgressIndicatorEnum indicator) {
        final sides = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: tracker(indicator),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((box) => box.decoration)
            .whereType<ShapeDecoration>()
            .map((d) => (d.shape as OutlinedBorder).side)
            .where((side) => side.width == FocusRingTapTarget.ringWidth);
        return sides.isEmpty ? null : sides.single;
      }

      testWidgets('Tab rings each tracker in turn and Enter activates it', (
        tester,
      ) async {
        await pumpTrackers(tester);
        const order = [
          ProgressIndicatorEnum.stars,
          ProgressIndicatorEnum.morphsUsed,
          ProgressIndicatorEnum.wordsUsed,
        ];
        for (final indicator in order) {
          expect(ringOn(tester, indicator), isNull);
        }

        for (final indicator in order) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          for (final other in order) {
            expect(
              ringOn(tester, other),
              other == indicator ? isNotNull : isNull,
              reason: 'only the focused tracker ($indicator) wears the ring',
            );
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(tapped.last, indicator);
        }
      });

      testWidgets('the ring clears 3:1 on both sides over the lit tracker', (
        tester,
      ) async {
        await pumpTrackers(tester);
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        }
        await tester.pumpAndSettle();

        final lit = ProgressIndicatorEnum.wordsUsed;
        final ring = ringOn(tester, lit)!;
        expect(ring.color, theme.pangea.goldGraphic);
        expect(
          ring.strokeAlign,
          BorderSide.strokeAlignOutside,
          reason:
              'outside the stadium the ring always lands on the field, '
              'whatever fills the tracker',
        );

        final ink = tester.widget<Ink>(
          find.descendant(of: tracker(lit), matching: find.byType(Ink)),
        );
        final wash = (ink.decoration! as ShapeDecoration).color!;
        final inkWell = tester.widget<InkWell>(
          find.descendant(of: tracker(lit), matching: find.byType(InkWell)),
        );
        expect(
          inkWell.focusColor,
          Colors.transparent,
          reason: 'a focus wash would darken the field inside the ring',
        );

        expect(
          contrastRatio(ring.color, scheme.surfaceContainer),
          greaterThanOrEqualTo(minGraphicRatio),
          reason: 'outside the ring: the pill field',
        );
        expect(
          contrastRatio(
            ring.color,
            Color.alphaBlend(wash, scheme.surfaceContainer),
          ),
          greaterThanOrEqualTo(minGraphicRatio),
          reason: 'inside the ring: the open-panel wash',
        );
      });

      testWidgets('each tracker is one named, focusable button', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpTrackers(tester);
        final l10n = L10n.of(tester.element(find.byType(Scaffold)));
        expectOneNodeControl(tester, '${l10n.stars}: 3');
        expectOneNodeControl(tester, '${l10n.grammar}: 3');
        expectOneNodeControl(tester, '${l10n.vocab}: 3');
        semantics.dispose();
      });

      testWidgets('no ring in touch highlight mode', (tester) async {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        await pumpTrackers(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(ringOn(tester, ProgressIndicatorEnum.stars), isNull);
      });
    });

    group('ringSideProperty on a Material button ($name)', () {
      Future<void> pumpButtons(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final style = ButtonStyle(
                    side: FocusRingTapTarget.ringSideProperty(context),
                  );
                  return Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add),
                        style: style,
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        style: style,
                        onPressed: () {},
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      BorderSide sideOf(WidgetTester tester, IconData icon) {
        final material = tester.widget<Material>(
          find.descendant(
            of: find.widgetWithIcon(IconButton, icon),
            matching: find.byType(Material),
          ),
        );
        return (material.shape! as OutlinedBorder).side;
      }

      testWidgets('the ring follows focus between buttons', (tester) async {
        await pumpButtons(tester);
        expect(sideOf(tester, Icons.add), BorderSide.none);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(sideOf(tester, Icons.add).color, theme.pangea.goldGraphic);
        expect(sideOf(tester, Icons.add).width, FocusRingTapTarget.ringWidth);
        expect(sideOf(tester, Icons.remove), BorderSide.none);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(sideOf(tester, Icons.add), BorderSide.none);
        expect(sideOf(tester, Icons.remove).color, theme.pangea.goldGraphic);
      });

      testWidgets('no ring in touch highlight mode', (tester) async {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        await pumpButtons(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(sideOf(tester, Icons.add), BorderSide.none);
      });
    });
  }
}
