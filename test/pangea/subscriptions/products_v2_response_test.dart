import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';

void main() {
  // Real-shaped fixture matching choreo `ProductsResponse` / `ProductPlanV2`
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

  group('ProductsResponse.fromJson', () {
    test('parses both plans with amount/currency/interval', () {
      final res = ProductsResponse.fromJson(productsFixture());
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
      final res = ProductsResponse.fromJson({
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
      final res = ProductsResponse.fromJson({"plans": <dynamic>[]});
      expect(res.plans, isEmpty);
    });

    test('a MISSING plans key throws (malformed, not an empty catalog)', () {
      expect(
        () => ProductsResponse.fromJson({}),
        throwsA(isA<FormatException>()),
      );
    });

    test('a null / non-list plans throws (malformed)', () {
      expect(
        () => ProductsResponse.fromJson({"plans": null}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ProductsResponse.fromJson({"plans": "oops"}),
        throwsA(isA<FormatException>()),
      );
    });

    test('echoes country when present', () {
      final json = productsFixture()..["country"] = "US";
      expect(ProductsResponse.fromJson(json).country, "US");
    });
  });
}
