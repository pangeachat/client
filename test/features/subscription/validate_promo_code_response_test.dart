import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/repo/validate_promo_code_response.dart';

// Field-by-field parse of the choreo `PromoCodeValidationResponse` (the
// display-only discount preview). All terms are top-level & optional; the shape
// is verified against the frontend contract.
void main() {
  group('ValidatePromoCodeResponse.fromJson — valid:true', () {
    test('percent coupon: full terms, currency null, unix-seconds expiry', () {
      final res = ValidatePromoCodeResponse.fromJson({
        "valid": true,
        "code": "WELCOME50",
        "discount_type": "percent",
        "percent_off": 50.0,
        "amount_off": null,
        "currency": null,
        "coupon_duration": "once",
        "restrictions": {
          "first_time_transaction": false,
          "minimum_amount": null,
          "minimum_amount_currency": null,
        },
        "discounted_price": {"amount": 499, "currency": "usd"},
        "expires_at": 1735689600,
        "reason": null,
      });

      expect(res.valid, true);
      expect(res.code, "WELCOME50");
      expect(res.discountType, "percent");
      expect(res.percentOff, 50.0);
      expect(res.amountOff, isNull);
      expect(res.currency, isNull);
      expect(res.couponDuration, "once");
      expect(res.expiresAt, 1735689600);
      expect(res.reason, isNull);
      expect(res.restrictions, isNotNull);
      expect(res.restrictions!.firstTimeTransaction, false);
      expect(res.discountedPrice, isNotNull);
      expect(res.discountedPrice!.amount, 499);
      expect(res.discountedPrice!.currency, "usd");
    });

    test('amount coupon: amount_off + top-level currency, percent_off null', () {
      final res = ValidatePromoCodeResponse.fromJson({
        "valid": true,
        "code": "5OFF",
        "discount_type": "amount",
        "percent_off": null,
        "amount_off": 500,
        "currency": "usd",
        "coupon_duration": "repeating",
        "restrictions": {"first_time_transaction": true},
        "discounted_price": null,
        "expires_at": null,
      });

      expect(res.discountType, "amount");
      expect(res.amountOff, 500);
      expect(res.percentOff, isNull);
      expect(res.currency, "usd");
      expect(res.couponDuration, "repeating");
      // discounted_price is present only when ?duration= is a known plan.
      expect(res.discountedPrice, isNull);
      expect(res.expiresAt, isNull);
      expect(res.restrictions!.firstTimeTransaction, true);
    });
  });

  group('ValidatePromoCodeResponse.fromJson — valid:false', () {
    test('invalid code carries a reason and null terms', () {
      for (final reason in const [
        "not_found_or_inactive",
        "expired",
        "max_redeemed",
      ]) {
        final res = ValidatePromoCodeResponse.fromJson({
          "valid": false,
          "reason": reason,
        });
        expect(res.valid, false);
        expect(res.reason, reason);
        expect(res.percentOff, isNull);
        expect(res.amountOff, isNull);
        expect(res.discountedPrice, isNull);
        expect(res.restrictions, isNull);
      }
    });

    test('below_minimum ALSO echoes the restrictions object', () {
      final res = ValidatePromoCodeResponse.fromJson({
        "valid": false,
        "reason": "below_minimum",
        "restrictions": {
          "first_time_transaction": false,
          "minimum_amount": 2000,
          "minimum_amount_currency": "usd",
        },
      });

      expect(res.valid, false);
      expect(res.reason, "below_minimum");
      expect(res.restrictions, isNotNull);
      expect(res.restrictions!.minimumAmount, 2000);
      expect(res.restrictions!.minimumAmountCurrency, "usd");
    });
  });

  group('PromoRestrictions.fromJson', () {
    test('first_time_transaction defaults to false when absent', () {
      final r = PromoRestrictions.fromJson({});
      expect(r.firstTimeTransaction, false);
      expect(r.minimumAmount, isNull);
      expect(r.minimumAmountCurrency, isNull);
    });
  });
}
