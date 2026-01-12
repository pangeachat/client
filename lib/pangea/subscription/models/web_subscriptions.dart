import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/subscription/models/base_subscription_info.dart';
import 'package:fluffychat/pangea/subscription/repo/subscription_repo.dart';

class WebSubscriptionInfo extends CurrentSubscriptionInfo {
  WebSubscriptionInfo({
    required super.userID,
    required super.availableSubscriptionInfo,
  });

  @override
  Future<void> setCurrentSubscription() async {
    if (currentSubscriptionId != null) return;
    try {
      final rcResponse = await SubscriptionRepo.getCurrentSubscriptionInfo(
        availableSubscriptionInfo.allProducts,
      );

      currentSubscriptionId = rcResponse.currentSubscriptionId;
      final currentSubscription =
          rcResponse.allSubscriptions?[currentSubscriptionId];

      if (currentSubscription != null) {
        expirationDate = DateTime.tryParse(currentSubscription.expiresDate);
        unsubscribeDetectedAt =
            currentSubscription.unsubscribeDetectedAt != null
                ? DateTime.parse(currentSubscription.unsubscribeDetectedAt!)
                : null;
      }
    } catch (err) {
      currentSubscriptionId = AppConfig.errorSubscriptionId;
    }

    if (currentSubscriptionId != null && currentSubscription == null) {
      Sentry.addBreadcrumb(
        Breadcrumb(message: "mismatch of productIds and currentSubscriptionID"),
      );
    }
  }
}
