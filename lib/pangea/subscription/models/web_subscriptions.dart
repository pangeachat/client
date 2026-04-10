import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
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
    RCSubscriptionResponseModel? rcResponse;
    try {
      rcResponse = await SubscriptionRepo.getCurrentSubscriptionInfo(
        availableSubscriptionInfo.allProducts,
      );

      currentSubscriptionId = rcResponse.currentSubscriptionId;
      final currentSubscription =
          rcResponse.allSubscriptions?[currentSubscriptionId];

      if (currentSubscription != null) {
        expirationDate = DateTime.tryParse(currentSubscription.expiresDate);
        if (expirationDate == null) {
          ErrorHandler.logError(
            m: "Failed to parse expiration date",
            data: {
              'expires_date': currentSubscription.expiresDate,
              'subscription_response': rcResponse.toJson(),
            },
          );
        }

        final unsubscribedAtEntry = currentSubscription.unsubscribeDetectedAt;
        if (unsubscribedAtEntry != null) {
          unsubscribeDetectedAt = DateTime.tryParse(unsubscribedAtEntry);
          if (unsubscribeDetectedAt == null) {
            ErrorHandler.logError(
              m: "Failed to parse unsubscribe detected at date",
              data: {
                'unsubscribe_detected_at': unsubscribedAtEntry,
                'subscription_response': rcResponse.toJson(),
              },
            );
          }
        } else {
          unsubscribeDetectedAt = null;
        }
      }
    } catch (err) {
      if (err is ChoreoException) {
        ErrorHandler.logError(
          e: err.errorMessage,
          data: {'subscription_response': rcResponse?.toJson()},
        );
      } else {
        ErrorHandler.logError(
          e: err,
          data: {'subscription_response': rcResponse?.toJson()},
        );
      }
      currentSubscriptionId = AppConfig.errorSubscriptionId;
    }

    if (currentSubscriptionId != null && currentSubscription == null) {
      Sentry.addBreadcrumb(
        Breadcrumb(message: "mismatch of productIds and currentSubscriptionID"),
      );
    }
  }
}
