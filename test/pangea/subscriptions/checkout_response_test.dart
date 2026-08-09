import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/enums/checkout_status_enum.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_response.dart';

void main() {
  group('CheckoutResponse.fromJson', () {
    test('created carries a sessionUrl and is resolved', () {
      final res = CheckoutResponse.fromJson({
        "status": "created",
        "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_123",
        "retryAfterSeconds": null,
      });
      expect(res.status, CheckoutStatus.created);
      expect(res.sessionUrl, "https://checkout.stripe.com/c/pay/cs_test_123");
      expect(res.isResolved, true);
      expect(res.isCreating, false);
    });

    test('parses appliedPromoCode when the session carries a discount', () {
      final res = CheckoutResponse.fromJson({
        "status": "created",
        "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_disc",
        "appliedPromoCode": "WELCOME50",
      });
      expect(res.appliedPromoCode, "WELCOME50");
      expect(res.isResolved, true);
    });

    test('appliedPromoCode is null when absent or explicitly null', () {
      final absent = CheckoutResponse.fromJson({
        "status": "created",
        "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_nodisc",
      });
      expect(absent.appliedPromoCode, isNull);

      final explicitNull = CheckoutResponse.fromJson({
        "status": "reused",
        "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_reuse",
        "appliedPromoCode": null,
      });
      expect(explicitNull.appliedPromoCode, isNull);
    });

    test('reused carries a sessionUrl and is resolved', () {
      final res = CheckoutResponse.fromJson({
        "status": "reused",
        "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_456",
      });
      expect(res.status, CheckoutStatus.reused);
      expect(res.isResolved, true);
      expect(res.isCreating, false);
    });

    test('creating carries retryAfterSeconds and no sessionUrl', () {
      final res = CheckoutResponse.fromJson({
        "status": "creating",
        "sessionUrl": null,
        "retryAfterSeconds": 2,
      });
      expect(res.status, CheckoutStatus.creating);
      expect(res.sessionUrl, isNull);
      expect(res.retryAfterSeconds, 2);
      expect(res.isCreating, true);
      expect(res.isResolved, false);
    });
  });
}
