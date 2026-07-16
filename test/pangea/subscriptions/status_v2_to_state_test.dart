import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';

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
  });
}
