import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/features/subscription/repo_v2/checkout_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_management_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

mixin PaymentPageMixin<T extends StatefulWidget> on State<T> {
  Future<void> processCheckoutRequest(CheckoutRequest request) async {
    _recordBeganPayment(request.planId, request.promoCode);
    final paymentLink = await _requestPaymentLink(request);
    if (paymentLink == null) return;
    await _launchPaymentLink(paymentLink);
  }

  void _recordBeganPayment(String planId, [String? promoCode]) {
    try {
      GoogleAnalytics.beginPurchaseSubscription(planId, promoCode, context);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"plan_id": planId, "promo_code": promoCode},
      );
    }
  }

  Future<String?> _requestPaymentLink(CheckoutRequest request) async {
    final checkoutResult = await showFutureLoadingDialog<String>(
      context: context,
      future: () async {
        final checkoutResult = await CheckoutRepo.instance.getPaymentLink(
          request,
        );

        final checkoutResponse = checkoutResult.result;
        if (checkoutResponse == null) {
          throw checkoutResult.asError ?? "Failed to checkout";
        }

        return checkoutResponse;
      },
    );

    return checkoutResult.result;
  }

  Future<void> _launchPaymentLink(String paymentLink) async {
    await SubscriptionManagementRepo.setBeganPayment();
    final success = await launchUrlString(
      paymentLink,
      webOnlyWindowName: "_self",
    );
    if (!success) {
      await SubscriptionManagementRepo.removeBeganPayment();
    }
  }
}
