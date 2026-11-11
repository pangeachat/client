import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/subscription/widgets/pro_features_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/free_trial_step_view.dart';

/// The trial page puts "No credit card required" at the top, above the Pro
/// features, so nobody reads the trial as asking for payment. See
/// `onboarding.instructions.md` § The experience.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    // The star background is a CachedNetworkImage, whose cache manager needs
    // path_provider; stub the channel to a temp dir.
    final tempDir = Directory.systemTemp.createTempSync('free_trial_step');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  testWidgets('no credit card required sits above the Pro features', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: FreeTrialStepView(forward: () {}),
      ),
    );
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    final noCard = find.text('No credit card required.');
    expect(noCard, findsOneWidget);
    expect(
      tester.getTopLeft(noCard).dy,
      lessThan(tester.getTopLeft(find.byType(ProFeaturesCard)).dy),
    );
  });
}
