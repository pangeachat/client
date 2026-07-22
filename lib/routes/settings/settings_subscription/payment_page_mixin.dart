import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/features/subscription/repo_v2/checkout_exceptions.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_management_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin PaymentPageMixin<T extends StatefulWidget> on State<T> {
  Future<void> processCheckoutRequest(CheckoutRequest request) async {
    _recordBeganPayment(request.planId, request.promoCode);

    final paymentLinkResult = await _requestPaymentLink(request);
    if (!mounted) return;

    final paymentLink = paymentLinkResult.result;

    final error = paymentLinkResult.error;
    if (error != null) {
      await _refreshOnCheckoutException(error);
    }

    if (paymentLink == null) return;
    await _launchPaymentLink(paymentLink, request.planId);
  }

  Future<void> _refreshOnCheckoutException(Object exception) async {
    if (exception is! ConflictCheckoutException) return;
    await MatrixState.pangeaController.subscriptionController.reinitialize(
      Matrix.of(context).client.userID!,
    );
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

  Future<Result<String>> _requestPaymentLink(CheckoutRequest request) =>
      showFutureLoadingDialog<String>(
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

  Future<void> _launchPaymentLink(String paymentLink, String planId) async {
    await SubscriptionManagementRepo.setBeganPayment(planId);
    final success = await launchUrlString(
      paymentLink,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: "_self",
    );
    if (!success) {
      await SubscriptionManagementRepo.removeBeganPayment();
    }
  }
}
