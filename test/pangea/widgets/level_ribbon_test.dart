import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/users/level_ribbon.dart';

/// The level symbol is the gold ribbon (was a bare `⭐`). These lock the two
/// modes the app uses: number-inside (profile card, cluster medal, progress
/// row) and plain glyph (the analytics header, where the level text sits
/// beside it).
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  testWidgets('renders the ribbon SVG with the level number overlaid', (
    tester,
  ) async {
    await pump(tester, const LevelRibbon(height: 44, level: 7));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('renders a plain ribbon glyph when level is null', (
    tester,
  ) async {
    await pump(tester, const LevelRibbon(height: 20));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('keeps the shield aspect ratio for the given height', (
    tester,
  ) async {
    await pump(tester, const LevelRibbon(height: 28.875, level: 1));
    final size = tester.getSize(find.byType(SvgPicture).first);
    expect(size.height, closeTo(28.875, 0.01));
    expect(size.width, closeTo(24.6667, 0.01));
  });
}
