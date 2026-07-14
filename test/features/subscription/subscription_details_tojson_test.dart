import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/utils/subscription_duration_enum.dart';

void main() {
  group('SubscriptionDetails.toJson currency omission (byte-for-byte)', () {
    test('mobile/RC (currency == null) OMITS the currency key entirely', () {
      final json = SubscriptionDetails(
        id: "rc_month",
        price: 9.99,
        duration: SubscriptionDuration.month,
        appId: "app_store_id",
      ).toJson();

      expect(json.containsKey('currency'), false);
      // The serialized shape is exactly today's keys, nothing more.
      expect(json.keys.toSet(), {
        'price',
        'id',
        'duration',
        'appId',
        'is_visible',
      });
    });

    test('web v2 (currency != null) includes the currency key', () {
      final json = SubscriptionDetails(
        id: "month",
        price: 9.99,
        currency: "usd",
        duration: SubscriptionDuration.month,
        appId: "stripe_id",
      ).toJson();

      expect(json['currency'], "usd");
    });

    test('round-trips through fromJson for both shapes', () {
      final mobile = SubscriptionDetails(id: "rc_month", price: 9.99);
      expect(SubscriptionDetails.fromJson(mobile.toJson()).currency, isNull);

      final web = SubscriptionDetails(
        id: "month",
        price: 9.99,
        currency: "eur",
      );
      expect(SubscriptionDetails.fromJson(web.toJson()).currency, "eur");
    });
  });
}
