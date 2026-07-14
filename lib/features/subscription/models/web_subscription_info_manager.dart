import 'package:flutter/foundation.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/features/subscription/models/products_v2_response.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/models/subscription_info_manager.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/models/subscription_status_v2.dart';
import 'package:fluffychat/features/subscription/repo/checkout_v2_repo.dart';
import 'package:fluffychat/features/subscription/repo/payment_link_repo.dart';
import 'package:fluffychat/features/subscription/repo/payment_link_request.dart';
import 'package:fluffychat/features/subscription/repo/status_v2_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/repo/subscription_repo.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/utils/v2_ui_gating.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class WebSubscriptionInfoManager implements SubscriptionInfoManager {
  @override
  Future<SubscriptionState> getCurrentSubscriptionInfo({
    String? stripeAppId,
  }) async {
    // v2 web path (flag-on): fetch /status and adapt into the existing state
    // shape (D7/I7). Keeps the same SubscriptionError-on-failure contract as
    // the RC branch below.
    if (Environment.subsV2WebEnabled && kIsWeb) {
      try {
        final status = await StatusV2Repo.get();
        if (isPaidWithoutPlan(status)) {
          // #4b: a paid entitlement should always map to a catalog plan. If it
          // does not, log it (this shouldn't happen) — the controller renders a
          // generic tile so the paying user still sees management + the
          // account-delete warning, rather than a broken/empty tile.
          ErrorHandler.logError(
            m: "v2 paid entitlement missing a catalog planId",
            s: StackTrace.current,
            data: {},
          );
        }
        return mapStatusV2ToState(
          status,
          stripeAppId: stripeAppId ?? kStripeAppIdFallback,
        );
      } catch (e, s) {
        ErrorHandler.logError(e: e, s: s, data: {});
        return SubscriptionError(error: e);
      }
    }

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

    // v2 web path (flag-on): resolve a planId from the duration (I4 whitelist,
    // throws on unknown), run /checkout (which POSTs `{planId}` and resolves the
    // session URL via the bounded poll, I1/I3), mark the pending web payment,
    // then redirect. The client-side prefilled_email append is dropped (I2 —
    // v2 prefills server-side).
    if (Environment.subsV2WebEnabled && kIsWeb) {
      final planId = kPlanIdToDuration.entries
          .firstWhere(
            (entry) => entry.value == duration,
            orElse: () => throw UnknownPlanIdException(duration.name),
          )
          .key;

      final sessionUrl = await CheckoutV2Repo.checkout(planId);

      await SubscriptionManagementRepo.setBeganWebPayment();
      launchUrlString(sessionUrl, webOnlyWindowName: "_self");
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
