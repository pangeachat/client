import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_type_enum.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';

// isV2PaidType is defined in subscription_status_v2.dart (imported above).

void main() {
  SubscriptionStatusResponse status({
    SubscriptionAccessLevel accessLevel = SubscriptionAccessLevel.none,
    bool trialEligible = false,
    bool trialClaimed = false,
    SubscriptionWinning? winning,
  }) => SubscriptionStatusResponse(
    accessLevel: accessLevel,
    entitlementSource: "cms",
    trialEligible: trialEligible,
    trialClaimed: trialClaimed,
    winning: winning,
    entitlements: [],
    manageEligible: false,
  );

  group('v2TrialOfferableFor (finding #1 — trial activatable)', () {
    test('eligible + unclaimed -> offerable', () {
      expect(
        status(trialEligible: true, trialClaimed: false).isTrialOfferable,
        isTrue,
      );
    });
    test('eligible but already claimed -> not offerable', () {
      expect(
        status(trialEligible: true, trialClaimed: true).isTrialOfferable,
        isFalse,
      );
    });
    test('not eligible -> not offerable', () {
      expect(status(trialEligible: false).isTrialOfferable, isFalse);
    });
  });

  group('isPaidWithoutPlan (finding #4 — paid access without planId)', () {
    test('paid + full + null planId -> true (anomaly)', () {
      expect(
        status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: const SubscriptionWinning(
            type: SubscriptionType.paid,
            status: "active",
            cancelAtPeriodEnd: false,
            provider: "cms",
          ),
        ).isPaidWithoutPlan,
        isTrue,
      );
    });
    test('paid + full + planId present -> false', () {
      expect(
        status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: const SubscriptionWinning(
            type: SubscriptionType.paid,
            status: "active",
            planId: "month",
            cancelAtPeriodEnd: false,
            provider: "cms",
          ),
        ).isPaidWithoutPlan,
        isFalse,
      );
    });
    test('comp -> false (legitimately no sellable plan)', () {
      expect(
        status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: const SubscriptionWinning(
            type: SubscriptionType.comp,
            status: "active",
            cancelAtPeriodEnd: false,
            provider: "cms",
          ),
        ).isPaidWithoutPlan,
        isFalse,
      );
    });
    test('seat -> false', () {
      expect(
        status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: const SubscriptionWinning(
            type: SubscriptionType.seat,
            status: "active",
            cancelAtPeriodEnd: false,
            provider: "cms",
          ),
        ).isPaidWithoutPlan,
        isFalse,
      );
    });
    test('trial -> false', () {
      expect(
        status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: const SubscriptionWinning(
            type: SubscriptionType.trial,
            cancelAtPeriodEnd: false,
            provider: "cms",
            status: "active",
          ),
        ).isPaidWithoutPlan,
        isFalse,
      );
    });
    test('individual (RC-era paid) + null planId -> true (billable)', () {
      expect(
        status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: const SubscriptionWinning(
            type: SubscriptionType.individual,
            status: "active",
            provider: "cms",
            cancelAtPeriodEnd: false,
          ),
        ).isPaidWithoutPlan,
        isTrue,
      );
    });

    test('no access -> false', () {
      expect(
        status(accessLevel: SubscriptionAccessLevel.none).isPaidWithoutPlan,
        isFalse,
      );
    });
  });

  group('isV2PaidType (finding #1 — individual is billable)', () {
    test(
      'paid -> billable',
      () => expect(SubscriptionType.paid.isBillable, isTrue),
    );
    test(
      'individual -> billable',
      () => expect(SubscriptionType.individual.isBillable, isTrue),
    );
    test(
      'seat -> not billable',
      () => expect(SubscriptionType.seat.isBillable, isFalse),
    );
    test(
      'comp -> not billable',
      () => expect(SubscriptionType.comp.isBillable, isFalse),
    );
    test(
      'trial -> not billable',
      () => expect(SubscriptionType.trial.isBillable, isFalse),
    );
  });
}
