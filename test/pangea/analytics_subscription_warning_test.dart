import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/analytics_subscription_warning.dart';

/// The analytics pages' warning that an unsubscribed learner's messages earn
/// no XP (#9119).
void main() {
  late L10n l10n;

  SubscriptionStatusResponse status(SubscriptionAccessLevel level) =>
      SubscriptionStatusResponse(
        accessLevel: level,
        entitlementSource: 'test',
        entitlements: const [],
      );

  final inactive = SubscriptionInactive(status(SubscriptionAccessLevel.none));
  final active = SubscriptionActive(status(SubscriptionAccessLevel.full));

  /// The purchase presentation resolves when the controller is built, from
  /// the platform: desktop is allowed to steer, Android outside the US is not.
  SubscriptionController controllerOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    try {
      return SubscriptionController();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<GoRouter> pumpWarning(
    WidgetTester tester,
    SubscriptionController subscription,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) {
            l10n = L10n.of(context);
            return Scaffold(
              body: AnalyticsSubscriptionWarning(subscription: subscription),
            );
          },
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Finder warningTitle() => find.text(l10n.analyticsSubscriptionWarningTitle);

  testWidgets('shows only while the status is known to be inactive', (
    tester,
  ) async {
    final subscription = controllerOn(TargetPlatform.linux)
      ..state.value = inactive;
    await pumpWarning(tester, subscription);

    expect(warningTitle(), findsOneWidget);
    expect(find.text(l10n.analyticsSubscriptionWarningBody), findsOneWidget);

    // A subscriber, a status still loading, and a failed lookup all may be
    // earning XP; the warning would be wrong or flash for them.
    for (final state in [
      active,
      SubscriptionLoading(),
      SubscriptionError(error: 'lookup failed'),
    ]) {
      subscription.state.value = state;
      await tester.pump();
      expect(warningTitle(), findsNothing, reason: '$state');
    }

    subscription.state.value = inactive;
    await tester.pump();
    expect(warningTitle(), findsOneWidget);
  });

  testWidgets('Subscribe opens the subscription page where steering is '
      'allowed', (tester) async {
    final subscription = controllerOn(TargetPlatform.linux)
      ..state.value = inactive;
    final router = await pumpWarning(tester, subscription);

    await tester.tap(find.widgetWithText(FilledButton, l10n.subscribe));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), contains('subscription'));
  });

  testWidgets('offers no purchase where the storefront forbids steering', (
    tester,
  ) async {
    final subscription = controllerOn(TargetPlatform.android)
      ..state.value = inactive;
    await pumpWarning(tester, subscription);

    expect(warningTitle(), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
