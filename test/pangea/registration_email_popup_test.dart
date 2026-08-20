import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/authentication/email_address_policy.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/signup/registration_email_popup.dart';

/// Covers pangeachat/synapse-pangea-chat#172. The resend control had no guard,
/// so every tap forced a fresh verification email.
void main() {
  Future<void> pumpPopup(
    WidgetTester tester,
    Future<void> Function() onResendEmail,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        // flutter_test renders every glyph as a square the size of the font,
        // so English strings measure roughly twice their real width and the
        // dialog's confirm button — untouched by this change — overflows its
        // capped box. Scaling text down keeps the harness about the resend
        // control rather than about the test font.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) =>
                  RegistrationEmailPopup(onResendEmail: onResendEmail),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    // The Localizations delegates resolve a frame after pumpWidget; without
    // this the subtree is still empty and nothing is findable.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder resendButton() => find.widgetWithText(TextButton, 'Resend');

  RegistrationEmailPopupState popupState(WidgetTester tester) => tester
      .state<RegistrationEmailPopupState>(find.byType(RegistrationEmailPopup));

  testWidgets('a second tap during the cooldown sends nothing', (tester) async {
    var sends = 0;
    await pumpPopup(tester, () async => sends++);

    await tester.tap(resendButton());
    await tester.pump();
    expect(sends, 1);

    // The control is disabled now, so a second tap cannot reach the callback.
    await tester.tap(find.byType(TextButton).last, warnIfMissed: false);
    await tester.pump();
    expect(sends, 1);
  });

  testWidgets('the control counts down and comes back', (tester) async {
    await pumpPopup(tester, () async {});

    await tester.tap(resendButton());
    await tester.pump();

    final cooldown = EmailAddressPolicy.resendCooldown.inSeconds;
    expect(find.text('Resend ($cooldown)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend ($cooldown)'), findsNothing);
    expect(find.text('Resend (${cooldown - 1})'), findsOneWidget);

    await tester.pump(EmailAddressPolicy.resendCooldown);
    expect(tester.widget<TextButton>(resendButton()).onPressed, isNotNull);
  });

  testWidgets('a send that failed does not cost the learner the wait', (
    tester,
  ) async {
    await pumpPopup(tester, () async => throw Exception('no connection'));

    await expectLater(popupState(tester).resendEmail(), throwsException);
    await tester.pump();

    expect(
      tester.widget<TextButton>(resendButton()).onPressed,
      isNotNull,
      reason: 'the control should be live again straight away',
    );
  });
}
