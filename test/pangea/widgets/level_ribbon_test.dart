import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/users/level_ribbon.dart';

/// The level symbol is the gold ribbon (was a bare `⭐`). These lock the three
/// modes the app uses: number-inside (the learner's own level, at cluster-medal
/// size), number-trailing (the inline chips, too short to hold a number inside
/// — #8918), and plain glyph (the analytics header, where the level text sits
/// beside it).
void main() {
  Future<void> pumpRibbon(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        // The test host can't load Material 3's ink-sparkle shader.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the ribbon SVG with the level number overlaid', (
    tester,
  ) async {
    await pumpRibbon(tester, const LevelRibbon(height: 44, level: 7));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // Inside is the default, and inside means inside: the digit is painted
    // within the shield, not beside it.
    expect(
      tester.getRect(find.byType(SvgPicture)).contains(
        tester.getRect(find.text('7')).center,
      ),
      isTrue,
    );
  });

  testWidgets('trailing placement puts the number beside the shield', (
    tester,
  ) async {
    await pumpRibbon(
      tester,
      const LevelRibbon(
        height: 18,
        level: 12,
        numberPlacement: LevelNumberPlacement.trailing,
      ),
    );
    final shield = tester.getRect(find.byType(SvgPicture));
    final number = tester.getRect(find.text('12'));
    expect(number.left, greaterThanOrEqualTo(shield.right));
  });

  testWidgets('shield and number announce as one "Level N", either placement', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final placement in LevelNumberPlacement.values) {
      await pumpRibbon(
        tester,
        LevelRibbon(height: 18, level: 7, numberPlacement: placement),
      );
      expect(find.bySemanticsLabel('Level 7'), findsOneWidget);
      // Never a loose digit alongside it.
      expect(find.bySemanticsLabel('7'), findsNothing);
    }
    semantics.dispose();
  });

  testWidgets('renders a plain ribbon glyph when level is null', (
    tester,
  ) async {
    await pumpRibbon(tester, const LevelRibbon(height: 20));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('keeps the shield aspect ratio for the given height', (
    tester,
  ) async {
    await pumpRibbon(tester, const LevelRibbon(height: 28.875, level: 1));
    final size = tester.getSize(find.byType(SvgPicture).first);
    expect(size.height, closeTo(28.875, 0.01));
    expect(size.width, closeTo(24.6667, 0.01));
  });
}
