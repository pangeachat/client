import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';

/// A failed save while the device is offline says so and what to do; any
/// other failure keeps its own message. See `onboarding.instructions.md`
/// § What onboarding reads and saves.
void main() {
  final status = ConnectionStatusController.instance.status;
  tearDown(() => status.value = ConnectionStatus.connected);

  Future<void> pumpWithError(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: OnboardingForwardButton(
            onPressed: () {},
            label: 'Next',
            error: Exception('save failed'),
          ),
        ),
      ),
    );
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  const offline = "You're offline.";

  testWidgets('offline, the error says so', (tester) async {
    status.value = ConnectionStatus.offline;
    await pumpWithError(tester);
    expect(find.textContaining(offline, findRichText: true), findsOneWidget);
  });

  testWidgets('online, the error keeps its own message', (tester) async {
    status.value = ConnectionStatus.connected;
    await pumpWithError(tester);
    expect(find.textContaining(offline, findRichText: true), findsNothing);
    expect(
      find.textContaining('something went wrong', findRichText: true),
      findsOneWidget,
    );
  });
}
