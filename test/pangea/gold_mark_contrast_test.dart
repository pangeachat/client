import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/routes/world/world_map_star_dot.dart';
import 'contrast_ratio.dart';

/// The sibling gold marks #8760 left out of scope (#8983). Each one's fill is
/// the information — an earned goal, a completed activity on the map — so each
/// owes 3:1 against the surface it actually composites on.
void main() {
  ThemeData themeFor(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: const Color(0xFF8560E0),
    ),
  );

  void expectClears(Color mark, Color background, String where) => expect(
    contrastRatio(mark, background),
    greaterThanOrEqualTo(minGraphicRatio),
    reason: '$where: $mark on $background',
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final theme = themeFor(brightness);
    final scheme = theme.colorScheme;
    final name = brightness.name;

    testWidgets('earned goal star clears 3:1 in $name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: GoalStatusWidget(
              goal: ActivityRoleGoal(id: 'g-0', description: 'Ask the price'),
              complete: true,
              isActive: true,
              showLabel: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gold = tester.widget<Icon>(find.byIcon(Icons.star)).color!;

      // The star's real backdrops. It rides the goal header card, which is
      // `surface` until the role is complete and a gold tint after; the active
      // goal's star sits on a translucent onSurface circle over either.
      final goldTint = Color.alphaBlend(
        AppConfig.goldByTheme(
          tester.element(find.byType(GoalStatusWidget)),
        ).withAlpha(40),
        scheme.surface,
      );
      final activeCircle = Color.alphaBlend(
        scheme.onSurface.withAlpha(26),
        scheme.surface,
      );
      // Tightest cell in the set: the active star on a complete (gold) card.
      final activeOnGoldTint = Color.alphaBlend(
        scheme.onSurface.withAlpha(26),
        goldTint,
      );

      for (final entry in {
        'header card': scheme.surface,
        'page card': scheme.surfaceContainerHighest,
        'complete card': goldTint,
        'active circle': activeCircle,
        'active on complete card': activeOnGoldTint,
      }.entries) {
        expectClears(gold, entry.value, '$name goal star on ${entry.key}');
      }
    });

    testWidgets('map trail star clears 3:1 on its circle in $name', (
      tester,
    ) async {
      for (final superStar in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: WorldMapStarDot(superStar: superStar)),
          ),
        );
        await tester.pumpAndSettle();

        // The glyph is centred in a `surface` circle it never reaches past, so
        // the circle — not the map tile under it — is what it composites on.
        final glyph = tester.widget<Icon>(
          find.byIcon(superStar ? Icons.hotel_class : Icons.star),
        );
        final dot = tester.widget<Container>(find.byType(Container));
        final circle = (dot.decoration! as BoxDecoration).color!;
        expect(circle, scheme.surface);
        expectClears(
          glyph.color!,
          circle,
          '$name ${superStar ? 'super ' : ''}trail star',
        );
      }
    });
  }
}
