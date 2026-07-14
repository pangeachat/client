import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/products_v2_response.dart';
import 'package:fluffychat/features/subscription/models/subscription_status_v2.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/utils/subscription_duration_enum.dart';
import 'package:fluffychat/features/subscription/utils/v2_subscription_catalog.dart';
import 'package:fluffychat/features/subscription/utils/v2_ui_gating.dart';

void main() {
  const stripeAppId = "stripe_app_1";

  const month = ProductV2(
    planId: "month",
    amount: 999,
    currency: "usd",
    interval: "month",
  );
  const year = ProductV2(
    planId: "year",
    amount: 9999,
    currency: "usd",
    interval: "year",
  );

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

  group('buildV2SubscriptionCatalog — products (D7 mapping + sort)', () {
    test('maps plans to SubscriptionDetails and sorts by price', () {
      final catalog = buildV2SubscriptionCatalog(
        // Deliberately reversed to prove the sort.
        [year, month],
        status(),
        stripeAppId: stripeAppId,
      );

      expect(catalog.available.map((s) => s.id).toList(), ["month", "year"]);
      final first = catalog.available.first;
      expect(first.price, 9.99);
      expect(first.currency, "usd");
      expect(first.appId, stripeAppId);
      expect(first.duration, SubscriptionDuration.month);
      // No trial in either list when the user is not eligible and has no active
      // trial.
      expect(catalog.available.where((s) => s.isTrial), isEmpty);
      expect(catalog.all.where((s) => s.isTrial), isEmpty);
      expect(catalog.all.map((s) => s.id).toList(), ["month", "year"]);
    });

    test('an unknown plan id throws (I4, fail closed)', () {
      const rogue = ProductV2(
        planId: "decade",
        amount: 100,
        currency: "usd",
        interval: "decade",
      );
      expect(
        () => buildV2SubscriptionCatalog(
          [month, rogue],
          status(),
          stripeAppId: stripeAppId,
        ),
        throwsA(isA<UnknownPlanIdException>()),
      );
    });

    test('a null status yields plans only, no trial anywhere', () {
      final catalog = buildV2SubscriptionCatalog(
        [month, year],
        null,
        stripeAppId: stripeAppId,
      );
      expect(catalog.available.length, 2);
      expect(catalog.all.length, 2);
      expect(catalog.available.any((s) => s.isTrial), isFalse);
    });
  });

  group('buildV2SubscriptionCatalog — trial synthesis (D3, finding #11)', () {
    test('eligible + unclaimed -> trial card in available AND all', () {
      final catalog = buildV2SubscriptionCatalog(
        [month, year],
        status(trialEligible: true, trialClaimed: false),
        stripeAppId: stripeAppId,
      );

      final availableTrial = catalog.available.where((s) => s.isTrial).toList();
      expect(availableTrial.length, 1);
      expect(availableTrial.single.id, kV2TrialId);
      expect(availableTrial.single.appId, "trial");
      expect(availableTrial.single.price, 0);
      // $0 trial sorts to the front of the price-sorted paywall list.
      expect(catalog.available.first.isTrial, isTrue);

      expect(catalog.all.where((s) => s.isTrial).length, 1);
    });

    test('eligible but ALREADY claimed -> no card on the paywall, but a trial '
        'stays in all so an active trial still resolves', () {
      final catalog = buildV2SubscriptionCatalog(
        [month, year],
        status(trialEligible: true, trialClaimed: true),
        stripeAppId: stripeAppId,
      );
      // Not offered on the paywall (already used) ...
      expect(catalog.available.where((s) => s.isTrial), isEmpty);
      // ... but still resolvable in `all` (trialEligible true).
      expect(catalog.all.where((s) => s.isTrial).length, 1);
    });

    test('active trial (not eligible to start) -> trial present in all only', () {
      final catalog = buildV2SubscriptionCatalog(
        [month, year],
        status(
          accessLevel: "full",
          trialEligible: false,
          winning: const WinningSummaryV2(type: "trial", status: "active"),
        ),
        stripeAppId: stripeAppId,
      );
      // The current-subscription getter must resolve the active trial tile ...
      expect(catalog.all.where((s) => s.isTrial).length, 1);
      expect(catalog.all.firstWhere((s) => s.isTrial).id, kV2TrialId);
      // ... but the paywall does not re-offer a trial the user is on.
      expect(catalog.available.where((s) => s.isTrial), isEmpty);
    });

    test('not eligible, no active trial -> no trial in either list', () {
      final catalog = buildV2SubscriptionCatalog(
        [month, year],
        status(accessLevel: "full"),
        stripeAppId: stripeAppId,
      );
      expect(catalog.available.where((s) => s.isTrial), isEmpty);
      expect(catalog.all.where((s) => s.isTrial), isEmpty);
    });

    test('the trial in `all` and `available` is ONE reused object (finding #3)',
        () {
      final catalog = buildV2SubscriptionCatalog(
        [month, year],
        status(trialEligible: true, trialClaimed: false),
        stripeAppId: stripeAppId,
      );
      final inAll = catalog.all.firstWhere((s) => s.isTrial);
      final inAvailable = catalog.available.firstWhere((s) => s.isTrial);
      expect(identical(inAll, inAvailable), isTrue);
    });
  });

  // finding #3: after the trial is activated the /status snapshot flips to
  // trialClaimed:true + an active trial. The paywall must stop offering it AND
  // the active-trial tile must still resolve as the current subscription.
  group('trial lifecycle transition (finding #3)', () {
    // The exact controller resolution predicate (subscription getter), so the
    // "resolves as current" claim is tested against real logic.
    bool resolves(List catalog, String id) => catalog.any(
      (s) => s.id.contains(id) || id.contains(s.id),
    );

    test('post-activation: not offered on paywall, resolves as current in all',
        () {
      final afterActivation = status(
        accessLevel: "full",
        trialEligible: false,
        trialClaimed: true,
        winning: const WinningSummaryV2(type: "trial", status: "active"),
      );

      // The server signal that drives v2TrialOfferable is now false.
      expect(v2TrialOfferableFor(afterActivation), isFalse);

      final catalog = buildV2SubscriptionCatalog(
        [month, year],
        afterActivation,
        stripeAppId: stripeAppId,
      );

      // No longer offered on the paywall ...
      expect(catalog.available.where((s) => s.isTrial), isEmpty);
      // ... but the active trial (subscriptionId == kV2TrialId) still resolves.
      expect(resolves(catalog.all, kV2TrialId), isTrue);
    });
  });
}
