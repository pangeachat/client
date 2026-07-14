import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/products_v2_response.dart';
import 'package:fluffychat/features/subscription/utils/subscription_duration_enum.dart';

void main() {
  // Real-shaped fixture matching choreo `ProductsV2Response` / `ProductPlanV2`
  // (products_v2_schema.py): amounts are minor units (999 == $9.99), currency
  // is lowercase ISO, planId is the catalog id the client sends to /checkout.
  Map<String, dynamic> productsFixture() => {
    "plans": [
      {
        "planId": "month",
        "amount": 999,
        "currency": "usd",
        "interval": "month",
        "interval_count": 1,
      },
      {
        "planId": "year",
        "amount": 9999,
        "currency": "usd",
        "interval": "year",
        "interval_count": 1,
      },
    ],
    "prices_localized_at_checkout": true,
    "country": null,
  };

  group('ProductsV2Response.fromJson', () {
    test('parses both plans with amount/currency/interval', () {
      final res = ProductsV2Response.fromJson(productsFixture());
      expect(res.plans.length, 2);
      expect(res.pricesLocalizedAtCheckout, true);
      expect(res.country, isNull);

      final month = res.plans[0];
      expect(month.planId, "month");
      expect(month.amount, 999);
      expect(month.currency, "usd");
      expect(month.interval, "month");
      expect(month.intervalCount, 1);

      final year = res.plans[1];
      expect(year.planId, "year");
      expect(year.amount, 9999);
    });

    test('interval_count defaults to 1 when absent', () {
      final res = ProductsV2Response.fromJson({
        "plans": [
          {
            "planId": "month",
            "amount": 999,
            "currency": "usd",
            "interval": "month",
          },
        ],
      });
      expect(res.plans.single.intervalCount, 1);
    });

    test('empty catalog yields empty plans (not an error)', () {
      final res = ProductsV2Response.fromJson({"plans": <dynamic>[]});
      expect(res.plans, isEmpty);
    });

    test('echoes country when present', () {
      final json = productsFixture()..["country"] = "US";
      expect(ProductsV2Response.fromJson(json).country, "US");
    });
  });

  group('productV2ToSubscriptionDetails (D7 mapper)', () {
    test('month 999/usd -> price 9.99, duration month, currency usd', () {
      final res = ProductsV2Response.fromJson(productsFixture());
      final details = productV2ToSubscriptionDetails(
        res.plans[0],
        stripeAppId: "stripe_app_xyz",
      );
      expect(details.id, "month");
      expect(details.price, closeTo(9.99, 1e-9));
      expect(details.currency, "usd");
      expect(details.duration, SubscriptionDuration.month);
      expect(details.appId, "stripe_app_xyz");
      expect(details.isVisible, true);
    });

    test('year 9999/usd -> price 99.99, duration year', () {
      final res = ProductsV2Response.fromJson(productsFixture());
      final details = productV2ToSubscriptionDetails(
        res.plans[1],
        stripeAppId: "stripe_app_xyz",
      );
      expect(details.price, closeTo(99.99, 1e-9));
      expect(details.duration, SubscriptionDuration.year);
    });

    test('unknown planId throws (I4) — never a null duration', () {
      const rogue = ProductV2(
        planId: "lifetime",
        amount: 19999,
        currency: "usd",
        interval: "year",
      );
      expect(
        () => productV2ToSubscriptionDetails(rogue, stripeAppId: "stripe"),
        throwsA(isA<UnknownPlanIdException>()),
      );
    });
  });
}
