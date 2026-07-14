import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/models/subscription_status_v2.dart';
import 'package:fluffychat/features/subscription/utils/v2_ui_gating.dart';

// isV2PaidType is defined in subscription_status_v2.dart (imported above).

void main() {
  SubscriptionStatusV2 status({
    String accessLevel = "none",
    bool trialEligible = false,
    bool trialClaimed = false,
    WinningSummaryV2? winning,
  }) => SubscriptionStatusV2(
    accessLevel: accessLevel,
    entitlementSource: "cms",
    trialEligible: trialEligible,
    trialClaimed: trialClaimed,
    winning: winning,
  );

  group('v2TrialOfferableFor (finding #1 — trial activatable)', () {
    test('eligible + unclaimed -> offerable', () {
      expect(
        v2TrialOfferableFor(status(trialEligible: true, trialClaimed: false)),
        isTrue,
      );
    });
    test('eligible but already claimed -> not offerable', () {
      expect(
        v2TrialOfferableFor(status(trialEligible: true, trialClaimed: true)),
        isFalse,
      );
    });
    test('not eligible -> not offerable', () {
      expect(v2TrialOfferableFor(status(trialEligible: false)), isFalse);
    });
    test('null status -> not offerable', () {
      expect(v2TrialOfferableFor(null), isFalse);
    });
  });

  group('isPaidWithoutPlan (finding #4 — paid access without planId)', () {
    test('paid + full + null planId -> true (anomaly)', () {
      expect(
        isPaidWithoutPlan(
          status(
            accessLevel: "full",
            winning: const WinningSummaryV2(type: "paid", status: "active"),
          ),
        ),
        isTrue,
      );
    });
    test('paid + full + planId present -> false', () {
      expect(
        isPaidWithoutPlan(
          status(
            accessLevel: "full",
            winning: const WinningSummaryV2(
              type: "paid",
              status: "active",
              planId: "month",
            ),
          ),
        ),
        isFalse,
      );
    });
    test('comp -> false (legitimately no sellable plan)', () {
      expect(
        isPaidWithoutPlan(
          status(
            accessLevel: "full",
            winning: const WinningSummaryV2(type: "comp", status: "active"),
          ),
        ),
        isFalse,
      );
    });
    test('seat -> false', () {
      expect(
        isPaidWithoutPlan(
          status(
            accessLevel: "full",
            winning: const WinningSummaryV2(type: "seat", status: "active"),
          ),
        ),
        isFalse,
      );
    });
    test('trial -> false', () {
      expect(
        isPaidWithoutPlan(
          status(
            accessLevel: "full",
            winning: const WinningSummaryV2(type: "trial", status: "active"),
          ),
        ),
        isFalse,
      );
    });
    test('individual (RC-era paid) + null planId -> true (billable)', () {
      expect(
        isPaidWithoutPlan(
          status(
            accessLevel: "full",
            winning: const WinningSummaryV2(
              type: "individual",
              status: "active",
            ),
          ),
        ),
        isTrue,
      );
    });

    test('no access -> false', () {
      expect(isPaidWithoutPlan(status(accessLevel: "none")), isFalse);
    });
  });

  group('isV2PaidType (finding #1 — individual is billable)', () {
    test('paid -> billable', () => expect(isV2PaidType("paid"), isTrue));
    test(
      'individual -> billable',
      () => expect(isV2PaidType("individual"), isTrue),
    );
    test('seat -> not billable', () => expect(isV2PaidType("seat"), isFalse));
    test('comp -> not billable', () => expect(isV2PaidType("comp"), isFalse));
    test('trial -> not billable', () => expect(isV2PaidType("trial"), isFalse));
    test('null -> not billable', () => expect(isV2PaidType(null), isFalse));
  });

  group('isTrialOfferable (finding #2 — path-aware trial gating)', () {
    test('v2 path uses the server signal (offerable)', () {
      expect(
        isTrialOfferable(
          v2Path: true,
          v2TrialOfferable: true,
          inTrialWindow: false, // outside the local window, but server-eligible
        ),
        isTrue,
      );
    });
    test('v2 path uses the server signal (not offerable)', () {
      expect(
        isTrialOfferable(
          v2Path: true,
          v2TrialOfferable: false,
          inTrialWindow: true, // local window open, but server says no
        ),
        isFalse,
      );
    });
    test('off-flag uses inTrialWindow (open)', () {
      expect(
        isTrialOfferable(
          v2Path: false,
          v2TrialOfferable: false,
          inTrialWindow: true,
        ),
        isTrue,
      );
    });
    test('off-flag uses inTrialWindow (closed)', () {
      expect(
        isTrialOfferable(
          v2Path: false,
          v2TrialOfferable: true,
          inTrialWindow: false,
        ),
        isFalse,
      );
    });
  });

  group('classifyCancelClick (finding #3 — cancel handler self-gated)', () {
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

    test('v2 path + eligible active -> v2Cancel', () {
      expect(
        classifyCancelClick(
          v2CancelPath: true,
          state: active(
            cancelable: true,
            cancelAtPeriodEnd: false,
            entitlementRef: "ent_1",
          ),
        ),
        CancelClickAction.v2Cancel,
      );
    });

    test('v2 path + already cancelling -> v2NoOp (NEVER legacy)', () {
      final action = classifyCancelClick(
        v2CancelPath: true,
        state: active(
          cancelable: true,
          cancelAtPeriodEnd: true,
          entitlementRef: "ent_1",
        ),
      );
      expect(action, CancelClickAction.v2NoOp);
      expect(action, isNot(CancelClickAction.legacy));
    });

    test('v2 path + not cancelable -> v2NoOp (NEVER legacy)', () {
      expect(
        classifyCancelClick(
          v2CancelPath: true,
          state: active(cancelable: false, entitlementRef: "ent_1"),
        ),
        CancelClickAction.v2NoOp,
      );
    });

    test('v2 path + inactive -> v2NoOp (NEVER legacy)', () {
      expect(
        classifyCancelClick(v2CancelPath: true, state: SubscriptionInactive()),
        CancelClickAction.v2NoOp,
      );
    });

    test('non-v2 path -> legacy (RC behavior preserved)', () {
      expect(
        classifyCancelClick(
          v2CancelPath: false,
          state: active(
            cancelable: true,
            cancelAtPeriodEnd: false,
            entitlementRef: "ent_1",
          ),
        ),
        CancelClickAction.legacy,
      );
    });
  });

  group('showUndatedPromoWarning (finding #2 — comp/seat NPE)', () {
    test('promotional with null expiration -> undated copy (no crash)', () {
      expect(
        showUndatedPromoWarning(isLifetime: false, expiration: null),
        isTrue,
      );
    });
    test('lifetime -> undated copy', () {
      expect(
        showUndatedPromoWarning(
          isLifetime: true,
          expiration: DateTime.utc(2200),
        ),
        isTrue,
      );
    });
    test('dated, not lifetime -> dated copy (format the date)', () {
      expect(
        showUndatedPromoWarning(
          isLifetime: false,
          expiration: DateTime.utc(2026, 8, 1),
        ),
        isFalse,
      );
    });
  });

  group('shouldWarnBeforeAccountDelete (finding #4 — delete safety)', () {
    test('paid + no management URL + v2 path -> WARN (safety net)', () {
      expect(
        shouldWarnBeforeAccountDelete(
          hasPaidSubscription: true,
          hasManagementUrl: false,
          v2Path: true,
        ),
        isTrue,
      );
    });
    test('paid + management URL + off v2 -> warn (today behavior)', () {
      expect(
        shouldWarnBeforeAccountDelete(
          hasPaidSubscription: true,
          hasManagementUrl: true,
          v2Path: false,
        ),
        isTrue,
      );
    });
    test('paid + no management URL + off v2 -> no warn (RC unchanged)', () {
      expect(
        shouldWarnBeforeAccountDelete(
          hasPaidSubscription: true,
          hasManagementUrl: false,
          v2Path: false,
        ),
        isFalse,
      );
    });
    test('not paid -> never warn', () {
      expect(
        shouldWarnBeforeAccountDelete(
          hasPaidSubscription: false,
          hasManagementUrl: true,
          v2Path: true,
        ),
        isFalse,
      );
    });
  });
}
