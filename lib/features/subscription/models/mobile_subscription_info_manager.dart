import 'package:collection/collection.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';

class MobileSubscriptionInfoManager implements SubscriptionInfoManager {
  @override
  Future<SubscriptionState> getCurrentSubscriptionInfo() async {
    try {
      await Purchases.invalidateCustomerInfoCache();
      final info = await Purchases.getCustomerInfo();
      final entitlement = info.entitlements.all.values.firstWhereOrNull((v) {
        if (!v.isActive) return false;
        final expr = v.expirationDate;
        return expr == null || DateTime.parse(expr).isAfter(DateTime.now());
      });

      if (entitlement == null) {
        return SubscriptionInactive();
      }

      final subscriptionId = entitlement.productIdentifier;
      final expirationDate = entitlement.expirationDate != null
          ? DateTime.parse(entitlement.expirationDate!)
          : null;
      final unsubscribeDetectedAt = entitlement.unsubscribeDetectedAt != null
          ? DateTime.parse(entitlement.unsubscribeDetectedAt!)
          : null;

      return SubscriptionActive(
        subscriptionId: subscriptionId,
        expirationDate: expirationDate,
        unsubscribeDetectedAt: unsubscribeDetectedAt,
      );
    } catch (err, s) {
      ErrorHandler.logError(
        m: "Failed to fetch revenuecat customer info",
        s: s,
        data: {},
      );
      return SubscriptionError(error: err);
    }
  }

  @override
  Future<void> submitSubscriptionChange(
    SubscriptionDetails subscription,
  ) async {
    final package = subscription.package;
    if (package == null) {
      final offerings = await Purchases.getOfferings();
      ErrorHandler.logError(
        m: "Tried to subscribe to SubscriptionDetails with Null revenuecat Package",
        s: StackTrace.current,
        data: {
          "selectedSubscription": subscription.toJson(),
          "offerings": offerings.toJson(),
        },
      );
      return;
    }

    await Purchases.purchasePackage(package);
  }
}
