import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/signup/signup.dart';
import 'package:fluffychat/routes/home/signup/signup_failure.dart';

/// Covers #8370. Email signup sent three ordinary outcomes to Sentry as errors
/// — a taken username, a homeserver rate limit, and a cancelled UIA request —
/// and showed the two server-side ones as raw English homeserver strings
/// ("User ID already taken.", "Rate limited") inside a red error dialog.
///
/// They are results of the form, not defects, so they classify here and come
/// back as localized copy the form can print. Anything that does not classify
/// keeps propagating, so real defects still reach Sentry.
void main() {
  MatrixException homeserverError(String errcode, String message) =>
      MatrixException.fromJson({'errcode': errcode, 'error': message});

  group('SignupFailure.from', () {
    test('a taken username classifies', () {
      expect(
        SignupFailure.from(
          homeserverError('M_USER_IN_USE', 'User ID already taken.'),
        ),
        SignupFailure.usernameTaken,
      );
    });

    test('a homeserver rate limit classifies', () {
      expect(
        SignupFailure.from(homeserverError('M_LIMIT_EXCEEDED', 'Rate limited')),
        SignupFailure.rateLimited,
      );
    });

    test('a cancelled UIA request classifies as abandoned', () {
      // The exact exception the matrix SDK's UiaRequest completes with when the
      // flow is cancelled — e.g. the user navigated away mid-signup.
      expect(
        SignupFailure.from(Exception('Request has been canceled')),
        SignupFailure.abandoned,
      );
    });

    test('an unexpected homeserver error does not classify', () {
      expect(
        SignupFailure.from(homeserverError('M_FORBIDDEN', 'Forbidden')),
        isNull,
        reason: 'anything unclassified must keep propagating and reporting',
      );
    });

    test('an arbitrary error does not classify', () {
      expect(SignupFailure.from(Exception('boom')), isNull);
    });
  });

  group('SignupFailure.localizedMessage', () {
    late BuildContext context;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (innerContext) {
              context = innerContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('both server outcomes read as localized form copy', (
      tester,
    ) async {
      await pump(tester);
      final l10n = L10n.of(context);

      expect(
        SignupFailure.usernameTaken.localizedMessage(context),
        l10n.usernameTakenPleaseChooseAnother,
      );
      expect(
        SignupFailure.rateLimited.localizedMessage(context),
        l10n.tooManyRequestsWarning,
      );
    });

    testWidgets('neither message is the raw homeserver string', (tester) async {
      await pump(tester);

      expect(
        SignupFailure.usernameTaken.localizedMessage(context),
        isNot('User ID already taken.'),
      );
      expect(
        SignupFailure.rateLimited.localizedMessage(context),
        isNot('Rate limited'),
      );
    });

    testWidgets('an abandoned attempt says nothing to the user', (
      tester,
    ) async {
      await pump(tester);

      expect(
        SignupFailure.abandoned.localizedMessage(context),
        isNull,
        reason: 'navigating away mid-request is control flow, not feedback',
      );
    });
  });

  group('the email signup form', () {
    Future<SignupPageController> pumpForm(WidgetTester tester) async {
      // Taller than the default 600 test surface: the form is a fixed Column,
      // so a short viewport overflows before the message under test is reached.
      tester.view.physicalSize = const Size(1200.0, 2000.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: const SignupPage(withEmail: true),
        ),
      );
      await tester.pumpAndSettle();
      return tester.state<SignupPageController>(find.byType(SignupPage));
    }

    testWidgets('prints a classified failure in the form itself', (
      tester,
    ) async {
      final controller = await pumpForm(tester);
      final message = SignupFailure.usernameTaken.localizedMessage(
        controller.context,
      )!;

      expect(find.text(message), findsNothing);

      controller.setSignupError(message);
      await tester.pump();

      expect(
        find.text(message),
        findsOneWidget,
        reason: 'the person needs the reason beside the fields they can fix',
      );
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: '#8370: a taken username is form feedback, not an error dialog',
      );
    });

    testWidgets('shows nothing while there is no failure', (tester) async {
      final controller = await pumpForm(tester);

      controller.setSignupError(
        SignupFailure.abandoned.localizedMessage(controller.context),
      );
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
