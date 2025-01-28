import 'package:sentry_flutter/sentry_flutter.dart';

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
    final rcResponse = await SubscriptionRepo.getCurrentSubscriptionInfo(
      userID,
      availableSubscriptionInfo.allProducts,
    );

    currentSubscriptionId = rcResponse.currentSubscriptionId;
    expirationDate = rcResponse.expirationDate;

    if (currentSubscriptionId != null && currentSubscription == null) {
      Sentry.addBreadcrumb(
        Breadcrumb(message: "mismatch of productIds and currentSubscriptionID"),
      );
    }
  }
}
