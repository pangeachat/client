import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/users/level_ribbon.dart';

/// The level symbol is the gold ribbon (was a bare `⭐`). These lock the two
/// modes the app uses: number-inside (profile card, cluster medal, progress
/// row) and plain glyph (the analytics header, where the level text sits
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
