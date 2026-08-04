import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/routes/chat/gain_points_animation.dart';

/// #7932 — the earn/lose XP particles are decoration, not readable text, so
/// they render at a fixed size. They used to be styled with `BotStyle.text`,
/// which multiplies by the settings > style font size factor, and the whole
/// animation grew or shrank with that slider.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  /// Renders the animation at [fontSizeFactor] and returns the size of one
  /// particle. Stops short of the end of the animation so the overlay-closing
  /// callback, which needs a live `MatrixState`, never runs.
  Future<Size> pumpParticle(WidgetTester tester, double fontSizeFactor) async {
    await AppSettings.fontSizeFactor.setItem(fontSizeFactor);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PointsGainedAnimation(
              points: 1,
              targetID: 'gain_points_test',
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

  testWidgets('particle size does not follow the font size setting', (
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
    await AppSettings.fontSizeFactor.setItem(2.0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PointsGainedAnimation(
              points: 1,
              targetID: 'gain_points_test',
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

  tearDownAll(() async {
    await AppSettings.fontSizeFactor.setItem(1.0);
  });
}
