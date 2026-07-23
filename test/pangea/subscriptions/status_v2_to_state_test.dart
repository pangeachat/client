import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription_view.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_options.dart';

void main() {
  SubscriptionStatusResponse status({
    SubscriptionAccessLevel accessLevel = SubscriptionAccessLevel.full,
    SubscriptionWinning? winning,
    List<SubscriptionEntitlement> entitlements = const [],
  }) => SubscriptionStatusResponse(
    accessLevel: accessLevel,
    entitlementSource: "cms",
    winning: winning,
    entitlements: entitlements,
  );

  group('mapStatusV2ToState — inactive branch (I7)', () {
    test('access_level none -> Inactive', () {
      final state = SubscriptionState.fromSubscriptionStatus(
        status(accessLevel: SubscriptionAccessLevel.none),
      );
      expect(state, isA<SubscriptionInactive>());
    });

    test('full but no winning -> Inactive (fail-safe)', () {
      final state = SubscriptionState.fromSubscriptionStatus(
        status(accessLevel: SubscriptionAccessLevel.full, winning: null),
      );
      expect(state, isA<SubscriptionInactive>());
    });

    test('full + winning -> Active (fail-safe)', () {
      final state = SubscriptionState.fromSubscriptionStatus(
        status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: SubscriptionWinning(status: "active"),
        ),
      );
      expect(state, isA<SubscriptionActive>());
    });

    Future<void> pumpSettingsSubscriptionsPage(
      WidgetTester tester,
      SubscriptionStatusResponse status,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SettingsSubscriptionView(
              closeButton: CloseButton(),
              subscriptionState: SubscriptionState.fromSubscriptionStatus(
                status,
              ),
              productsState: AsyncLoaded([]),
              reloadStatus: () {},
              onEnterDiscountCode: () async {},
              onTapSubscription: (_) async {},
              selectedSubscription: ValueNotifier(null),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'settings subscription view renders no-access content for status with full but no winning',
      (tester) async {
        final s = status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: null,
        );

        await pumpSettingsSubscriptionsPage(tester, s);
        expect(find.byType(FullAccessContent), findsNothing);
        expect(find.byType(SubscriptionOptions), findsOneWidget);
      },
    );

    testWidgets(
      'settings subscription view renders full-access content for status with full + winning',
      (tester) async {
        final s = status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: SubscriptionWinning(status: "active"),
        );

        await pumpSettingsSubscriptionsPage(tester, s);
        expect(find.byType(FullAccessContent), findsOneWidget);
        expect(find.byType(SubscriptionOptions), findsNothing);
      },
    );
  });
}
