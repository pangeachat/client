import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart';
import 'package:fluffychat/routes/world/world_map_star_dot.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';
import 'package:fluffychat/widgets/goal_diamond.dart';
import 'contrast_ratio.dart';

/// The sibling gold marks #8760 left out of scope (#8983). Each one's mark is
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

    testWidgets('earned goal diamond clears 3:1 in $name', (tester) async {
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

      // A completed goal is a diamond, never a star: its gold edge is what
      // reads against the backdrop.
      final diamond = tester.widget<GoalDiamond>(find.byType(GoalDiamond));
      expect(diamond.earned, isTrue);
      final gold = diamond.edgeIn(
        Theme.of(tester.element(find.byType(GoalDiamond))),
      );

      // The diamond's real backdrops. It rides the goal header card, which is
      // `surface` until the role is complete and a gold tint after; the active
      // goal's diamond sits on a translucent onSurface circle over either.
      final goldTint = Color.alphaBlend(
        Theme.of(
          tester.element(find.byType(GoalStatusWidget)),
        ).pangea.goldFixedDim.withAlpha(40),
        scheme.surface,
      );
      final activeCircle = Color.alphaBlend(
        scheme.onSurface.withAlpha(26),
        scheme.surface,
      );
      // Tightest cell in the set: the active diamond on a complete (gold)
      // card.
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
        expectClears(gold, entry.value, '$name goal diamond on ${entry.key}');
      }
    });

    testWidgets('map completed stamp clears 3:1 on its disc in $name', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(body: WorldMapStarDot()),
        ),
      );
      await tester.pumpAndSettle();

      // The rings and check are drawn inside the stamp's gold disc, never
      // past it, so the disc — not the map tile under it — is what they
      // composite on.
      expect(find.byType(CompletedStamp), findsOneWidget);
      final stampTheme = Theme.of(tester.element(find.byType(CompletedStamp)));
      expectClears(
        CompletedStamp.inkOf(stampTheme),
        CompletedStamp.paperOf(stampTheme),
        '$name completed stamp',
      );
    });
  }
}
