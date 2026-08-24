import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/chat/gain_points_animation.dart';

/// #7932 — the earn/lose XP particles are decoration, not readable text, so
/// they render at a fixed size. They used to be styled with `BotStyle.text`,
/// which multiplied by the settings > style font size factor, and the whole
/// animation grew or shrank with that slider.
///
/// #7719 removed that slider; the device's own text-size setting drives text
/// size now. The invariant is unchanged, so this drives the device scaler
/// instead: the particles fly along trajectories measured in fixed pixels, and
/// a scaled glyph would drift off its own path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Renders the animation at [textScale] and returns the size of one
  /// particle. Stops short of the end of the animation so the overlay-closing
  /// callback, which needs a live `MatrixState`, never runs.
  Future<Size> pumpParticle(WidgetTester tester, double textScale) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(
            body: Center(
              child: PointsGainedAnimation(
                points: 1,
                targetID: 'gain_points_test',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final size = tester.getSize(find.text('+').first);

    // Dispose the widget so its ticker stops before the test ends.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    return size;
  }

  testWidgets('particle size does not follow the device text scaler', (
    tester,
  ) async {
    final small = await pumpParticle(tester, 0.5);
    final normal = await pumpParticle(tester, 1.0);
    final large = await pumpParticle(tester, 2.0);

    expect(small, normal);
    expect(large, normal);
  });

  testWidgets('particles render at the default message font size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: const Scaffold(
            body: Center(
              child: PointsGainedAnimation(
                points: 1,
                targetID: 'gain_points_test',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final text = tester.widget<Text>(find.text('+').first);
    expect(text.style?.fontSize, AppConfig.messageFontSize * 1.2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
