import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/routes/chat/gain_points_animation.dart';

/// #9112 — the XP burst is decoration: it repeats what the progress bar shows.
/// It wears the bar's gold rather than the 3:1 mark gold, and a screen reader
/// never reads its "+" glyphs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Stops short of the end of the animation so the overlay-closing callback,
  /// which needs a live `MatrixState`, never runs.
  Future<void> pumpBurst(
    WidgetTester tester, {
    required int points,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Center(
            child: PointsGainedAnimation(
              points: points,
              targetID: 'gain_points_test',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// Dispose the widget so its ticker stops before the test ends.
  Future<void> disposeBurst(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: SizedBox()));

  Color glyphColor(WidgetTester tester, String glyph) =>
      tester.widget<Text>(find.text(glyph).first).style!.color!;

  for (final brightness in Brightness.values) {
    testWidgets('gain glyphs wear the progress bar gold in $brightness', (
      tester,
    ) async {
      await pumpBurst(tester, points: 3, brightness: brightness);
      expect(glyphColor(tester, '+'), PangeaColors.of(brightness).goldFixedDim);
      await disposeBurst(tester);
    });
  }

  testWidgets('loss glyphs stay the error red', (tester) async {
    await pumpBurst(tester, points: -3);
    expect(
      glyphColor(tester, '-'),
      PangeaColors.of(Brightness.light).errorGraphic,
    );
    await disposeBurst(tester);
  });

  testWidgets('the glyphs are hidden from screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBurst(tester, points: 3);
    expect(find.text('+'), findsWidgets);
    expect(find.bySemanticsLabel('+'), findsNothing);
    await disposeBurst(tester);
    semantics.dispose();
  });
}
