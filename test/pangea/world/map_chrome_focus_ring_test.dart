import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/world/hex_level_badge.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/routes/world/xp_border_painter.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import '../contrast_ratio.dart';
import '../one_node_control.dart';

/// #8880: the map's zoom controls and the cluster's stat trackers showed focus
/// only through Material's own wash (1.17:1 to 1.45:1). Both now wear the
/// app's gold focus ring; the level badges wear the two-tone ring (#9114).
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

    /// #9114: the level medal and the narrow bar's hexagon badge overhang the
    /// XP ring and the map, where the gold ring measures 1.0 to 2.9:1, so
    /// they wear the pins' two-tone pair, traced along their own outline.
    group('level badges ($name)', () {
      const inner = FocusRingTapTarget.twoToneInner;
      const outer = FocusRingTapTarget.twoToneOuter;

      var taps = 0;
      final badges = <(String, Widget, double)>[
        (
          'level medal',
          ClusterLevelMedal(level: 3, onTap: () => taps++),
          BorderSide.strokeAlignOutside,
        ),
        (
          'hexagon badge',
          HexLevelBadge(
            level: 3,
            onTap: () => taps++,
            width: 42,
            height: 36,
            fontSize: 16,
          ),
          // Inside its own box, where the bar's shimmer mask reaches (#7801).
          BorderSide.strokeAlignInside,
        ),
      ];

      Future<void> pumpBadge(WidgetTester tester, Widget badge) async {
        taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: Center(
                child: Material(type: MaterialType.transparency, child: badge),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      /// The outline-traced ring bands currently painted, narrowest first.
      List<BorderSide> bands(WidgetTester tester) =>
          tester
              .widgetList<DecoratedBox>(find.byType(DecoratedBox))
              .map((box) => box.decoration)
              .whereType<ShapeDecoration>()
              .map((d) => d.shape)
              .whereType<PathBorder>()
              .map((shape) => shape.side)
              .where((side) => side != BorderSide.none)
              .toList()
            ..sort((a, b) => a.width.compareTo(b.width));

      for (final (badgeName, badge, align) in badges) {
        testWidgets('Tab rings the $badgeName two-tone; Enter activates it', (
          tester,
        ) async {
          await pumpBadge(tester, badge);
          expect(bands(tester), isEmpty);

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final painted = bands(tester);
          expect(painted, hasLength(2));
          final [edge, beyond] = painted;
          // Light toward the badge, dark toward what surrounds it.
          final outside = align == BorderSide.strokeAlignOutside;
          expect(edge.color, outside ? inner : outer);
          expect(beyond.color, outside ? outer : inner);
          expect(edge.width, FocusRingTapTarget.ringWidth);
          expect(beyond.width, 2 * FocusRingTapTarget.ringWidth);
          expect([edge.strokeAlign, beyond.strokeAlign], everyElement(align));

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(taps, 1);
        });

        testWidgets('the $badgeName is one named, focusable button', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          await pumpBadge(tester, badge);
          final l10n = L10n.of(tester.element(find.byType(Scaffold)));
          expectOneNodeControl(tester, '${l10n.level} 3');
          semantics.dispose();
        });

        testWidgets('no ring on the $badgeName in touch highlight mode', (
          tester,
        ) async {
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTouch;
          await pumpBadge(tester, badge);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(bands(tester), isEmpty);
        });
      }

      const backdrop = Color(0xFF0000FF);
      const pad = 8;
      bool isDark(Color c) => c.r < 0.25 && c.g < 0.25 && c.b < 0.25;
      bool isLight(Color c) => c.r > 0.95 && c.g > 0.95 && c.b > 0.95;

      /// [badge] rendered keyboard-focused over [backdrop] with [pad] clear on
      /// every side, as a pixel reader over the capture and its size.
      Future<(Color Function(int, int), int, int)> captureFocused(
        WidgetTester tester,
        Widget badge,
      ) async {
        final key = GlobalKey();
        await pumpBadge(
          tester,
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: backdrop,
              child: Padding(
                padding: EdgeInsets.all(pad.toDouble()),
                child: badge,
              ),
            ),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final (bytes, width, height) = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return (data!, image.width, image.height);
        }))!;
        Color at(int x, int y) {
          final i = (y * width + x) * 4;
          return Color.fromARGB(
            bytes.getUint8(i + 3),
            bytes.getUint8(i),
            bytes.getUint8(i + 1),
            bytes.getUint8(i + 2),
          );
        }

        return (at, width, height);
      }

      testWidgets('the medal ring traces the shield, light against it', (
        tester,
      ) async {
        final (at, _, _) = await captureFocused(
          tester,
          ClusterLevelMedal(level: 3, onTap: () {}),
        );
        // A column through the shield's flat top, which sits one ring
        // clearance (two bands) inside the medal's box.
        const x = pad + 22;
        const top = pad + 2 * FocusRingTapTarget.ringWidth;
        expect(isDark(at(x, top.toInt() - 3)), isTrue, reason: 'dark beyond');
        expect(isLight(at(x, top.toInt() - 1)), isTrue, reason: 'light band');
        final shield = at(x, top.toInt() + 1);
        expect(
          shield.r > 0.8 && shield.b < 0.3,
          isTrue,
          reason: 'the ring leaves the shield itself gold, got $shield',
        );
        expect(at(pad, pad), backdrop, reason: 'nothing at the box corner');
      });

      testWidgets('the hexagon ring paints nothing outside its box (#7801)', (
        tester,
      ) async {
        const w = 42, h = 36;
        final (at, width, height) = await captureFocused(
          tester,
          HexLevelBadge(
            level: 3,
            onTap: () {},
            width: w.toDouble(),
            height: h.toDouble(),
            fontSize: 16,
          ),
        );
        final bled = [
          for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++)
              if ((x < pad || x >= pad + w || y < pad || y >= pad + h) &&
                  at(x, y) != backdrop)
                (x, y),
        ];
        expect(bled, isEmpty, reason: "the bar's shimmer masks only the box");
        // A column through the hexagon's flat top: the dark band on the edge,
        // then the light band inside it.
        expect(isDark(at(pad + w ~/ 2, pad + 1)), isTrue);
        expect(isLight(at(pad + w ~/ 2, pad + 3)), isTrue);
      });

      test('one band clears 3:1 against every neighbour of the badges', () {
        // Against each other the bands clear 9:1 even over white, where the
        // translucent dark band is palest, so one of them clears 3:1 against
        // any backdrop, map tiles included (WCAG technique C40).
        for (final backdrop in [Colors.white, Colors.black]) {
          expect(
            contrastRatio(inner, Color.alphaBlend(outer, backdrop)),
            greaterThanOrEqualTo(9.0),
          );
        }
        final neighbours = {
          'the shield': theme.pangea.goldFixedDim,
          'the lit shield': theme.pangea.goldHighlight,
          'the XP track': XpBorderPainter.trackColorFor(theme),
          'the XP arc': XpBorderPainter.arcColorFor(theme),
          'the pill field': scheme.surfaceContainer,
        };
        for (final MapEntry(key: where, value: color) in neighbours.entries) {
          expect(
            max(
              contrastRatio(inner, color),
              contrastRatio(Color.alphaBlend(outer, color), color),
            ),
            greaterThanOrEqualTo(minGraphicRatio),
            reason: where,
          );
        }
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
