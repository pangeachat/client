import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/utils/cancel_eligibility.dart';

void main() {
  SubscriptionActive active({
    bool? cancelable,
    bool? cancelAtPeriodEnd,
    String? entitlementRef,
  }) => SubscriptionActive(
    subscriptionId: "month",
    cancelable: cancelable,
    cancelAtPeriodEnd: cancelAtPeriodEnd,
    entitlementRef: entitlementRef,
  );

  group('shouldShowV2Cancel truth table (I5)', () {
    test('cancelable + not cancelling + ref -> show', () {
      expect(
        shouldShowV2Cancel(
          active(
            cancelable: true,
            cancelAtPeriodEnd: false,
            entitlementRef: "ent_1",
          ),
        ),
        true,
      );
    });

    test('already cancel-at-period-end -> hide', () {
      expect(
        shouldShowV2Cancel(
          active(
            cancelable: true,
            cancelAtPeriodEnd: true,
            entitlementRef: "ent_1",
          ),
        ),
        false,
      );
    });

    test('not cancelable -> hide', () {
      expect(
        shouldShowV2Cancel(
          active(
            cancelable: false,
            cancelAtPeriodEnd: false,
            entitlementRef: "ent_1",
          ),
        ),
        false,
      );
    });

    test('null ref -> hide', () {
      expect(
        shouldShowV2Cancel(active(cancelable: true, cancelAtPeriodEnd: false)),
        false,
      );
    });

    test('mobile/RC (all null) -> hide', () {
      expect(shouldShowV2Cancel(active()), false);
    });

    test('null cancelAtPeriodEnd is treated as not cancelling', () {
      expect(
        shouldShowV2Cancel(active(cancelable: true, entitlementRef: "ent_1")),
        true,
      );
    });
  });
}
