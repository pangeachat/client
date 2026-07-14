import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/checkout_response.dart';

void main() {
  group('CheckoutResponse.fromJson', () {
    test('created carries a sessionUrl and is resolved', () {
      final res = CheckoutResponse.fromJson({
        "status": "created",
        "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_123",
        "retryAfterSeconds": null,
      });
      expect(res.status, "created");
      expect(res.sessionUrl, "https://checkout.stripe.com/c/pay/cs_test_123");
      expect(res.isResolved, true);
      expect(res.isCreating, false);
    });

    test('reused carries a sessionUrl and is resolved', () {
      final res = CheckoutResponse.fromJson({
        "status": "reused",
        "sessionUrl": "https://checkout.stripe.com/c/pay/cs_test_456",
      });
      expect(res.status, "reused");
      expect(res.isResolved, true);
      expect(res.isCreating, false);
    });

    test('creating carries retryAfterSeconds and no sessionUrl', () {
      final res = CheckoutResponse.fromJson({
        "status": "creating",
        "sessionUrl": null,
        "retryAfterSeconds": 2,
      });
      expect(res.status, "creating");
      expect(res.sessionUrl, isNull);
      expect(res.retryAfterSeconds, 2);
      expect(res.isCreating, true);
      expect(res.isResolved, false);
    });
  });
}
