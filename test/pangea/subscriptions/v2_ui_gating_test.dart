import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_type_enum.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';

void main() {
  SubscriptionStatusResponse status({
    SubscriptionAccessLevel accessLevel = SubscriptionAccessLevel.none,
    bool trialEligible = false,
    bool trialClaimed = false,
    SubscriptionWinning? winning,
  }) => SubscriptionStatusResponse(
    accessLevel: accessLevel,
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
    test('unknown winning type + null planId -> false', () {
      // A type the client doesn't know (e.g. the retired `individual` label)
      // parses to null and is not treated as billable.
      expect(
        status(
          accessLevel: SubscriptionAccessLevel.full,
          winning: SubscriptionWinning.fromJson(const {
            "type": "individual",
            "status": "active",
          }),
        ).isPaidWithoutPlan,
        isFalse,
      );
    });

    test('no access -> false', () {
      expect(
        status(accessLevel: SubscriptionAccessLevel.none).isPaidWithoutPlan,
        isFalse,
      );
    });
  });

  group('isBillable (finding #1 — only paid is billable)', () {
    test(
      'paid -> billable',
      () => expect(SubscriptionType.paid.isBillable, isTrue),
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
