import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo/payment_link_repo.dart';
import 'package:fluffychat/features/subscription/repo/payment_link_request.dart';
import 'package:fluffychat/features/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_repo.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class WebSubscriptionInfoManager implements SubscriptionInfoManager {
  @override
  Future<SubscriptionState> getCurrentSubscriptionInfo() async {
    try {
      final res = await SubscriptionRepo.getCurrentSubscriptionInfo(null);
      final subscriptionId = res.currentSubscriptionId;
      if (subscriptionId == null) {
        return SubscriptionInactive();
      }

      final subscription = res.allSubscriptions?[subscriptionId];
      if (subscription == null) {
        return SubscriptionActive(subscriptionId: subscriptionId);
      }

      final expirationDate = DateTime.tryParse(subscription.expiresDate);

      DateTime? unsubscribeDetectedAt;
      final unsubscribedAtEntry = subscription.unsubscribeDetectedAt;
      if (unsubscribedAtEntry != null) {
        unsubscribeDetectedAt = DateTime.tryParse(unsubscribedAtEntry);
      }

      return SubscriptionActive(
        subscriptionId: subscriptionId,
        expirationDate: expirationDate,
        unsubscribeDetectedAt: unsubscribeDetectedAt,
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return SubscriptionError(error: e);
    }
  }

  @override
  Future<void> submitSubscriptionChange(
    SubscriptionDetails subscription,
  ) async {
    final duration = subscription.duration;
    if (duration == null) {
      ErrorHandler.logError(
        m: "Tried to subscribe to web SubscriptionDetails with Null duration",
        s: StackTrace.current,
        data: {"selectedSubscription": subscription.toJson()},
      );
      return;
    }
    final request = PaymentLinkRequest(duration: duration, isPromo: false);

    final result = await PaymentLinkRepo.get(request);
    if (result.isError) throw result.error!;
    final paymentLink = result.result!;

    await SubscriptionManagementRepo.setBeganWebPayment();
    launchUrlString(paymentLink, webOnlyWindowName: "_self");
  }
}
