import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';

/// The bot takes the seed the learner tapped, and a setting is not an
/// inherited widget. Twice now the widget has been left reading a value
/// nothing rebuilds it for, so it kept the colour it first drew while the
/// rest of the app changed around it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  /// Pumps until a still is on screen that is not [previous]. The old image
  /// stays up while a new one renders, so waiting for merely any image reads
  /// the stale one back and passes whatever the widget does.
  Future<Object?> settledImage(WidgetTester tester, {Object? previous}) async {
    Object? latest;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      if (images.isEmpty) continue;
      latest = images.first.image;
      if (latest != null && !identical(latest, previous)) return latest;
    }
    return latest;
  }

  testWidgets('the bot follows a change of theme colour', (tester) async {
    Widget app(int seed) => MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(seed),
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ),
      ),
      home: const Scaffold(
        body: Center(
          child: BotFace(
            width: 48,
            expression: BotExpression.idle,
            animate: false,
          ),
        ),
      ),
    );

    await AppSettings.colorSchemeSeedInt.setItem(0xFF8560E0);
    await tester.pumpWidget(app(0xFF8560E0));
    final purple = await settledImage(tester);
    expect(purple, isNotNull, reason: 'the still must reach the widget');

    // What tapping a swatch does: set the seed, rebuild the theme.
    await AppSettings.colorSchemeSeedInt.setItem(0xFF2196F3);
    await tester.pumpWidget(app(0xFF2196F3));
    final blue = await settledImage(tester, previous: purple);

    expect(
      identical(purple, blue),
      isFalse,
      reason:
          'the bot kept its old colour through a theme change; it reads '
          'the seed, which is not an inherited widget, so it needs a theme '
          'dependency to be rebuilt at all',
    );
  });
}
