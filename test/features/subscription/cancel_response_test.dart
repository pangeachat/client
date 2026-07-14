import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/cancel_response.dart';

void main() {
  group('CancelResponse.fromJson', () {
    test('parses the cancel_at_period_end success shape', () {
      final res = CancelResponse.fromJson({
        "status": "cancel_at_period_end",
        "entitlementRef": "ent_123",
      });
      expect(res.status, "cancel_at_period_end");
      expect(res.entitlementRef, "ent_123");
    });

    test('tolerates a missing entitlementRef', () {
      final res = CancelResponse.fromJson({"status": "cancel_at_period_end"});
      expect(res.status, "cancel_at_period_end");
      expect(res.entitlementRef, "");
    });
  });
}
