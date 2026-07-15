import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/features/subscription/repo_v2/checkout_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_response.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_popup.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_provider.dart';
import 'package:fluffychat/routes/settings/settings_subscription/selected_subscription_popup.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription_view.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_status_provider.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SettingsSubscription extends StatefulWidget {
  final Widget closeButton;
  const SettingsSubscription({super.key, required this.closeButton});

  @override
  SettingsSubscriptionState createState() => SettingsSubscriptionState();
}

class SettingsSubscriptionState extends State<SettingsSubscription> {
  final ValueNotifier<ProductPlan?> _selectedSubscription = ValueNotifier(null);

  @override
  void dispose() {
    _selectedSubscription.dispose();
    super.dispose();
  }

  Future<Result<ValidatePromoCodeResponse>> _validatePromoCode(String code) =>
      ValidatePromoCodeRepo.instance.get(
        ValidatePromoCodeRequest(
          userID: Matrix.of(context).client.userID!,
          code: code,
        ),
      );

  Future<void> _onEnterDiscountCode() async {
    final resp = await showDialog<CheckoutRequest>(
      context: context,
      builder: (context) => ProductsProvider(
        builder: (context, productsState) => DiscountCodePopup(
          validateCode: _validatePromoCode,
          productsState: productsState,
        ),
      ),
    );
    if (resp == null) return;

    _recordBeganPayment(resp.planId, resp.promoCode);

    final paymentLink = await _requestPaymentLink(resp);
    if (paymentLink == null) return;

    await _launchPaymentLink(paymentLink);
  }

  Future<void> _onTapSubscription(ProductPlan plan) async {
    _selectedSubscription.value = plan;
    final resp = await showDialog(
      context: context,
      builder: (context) => SelectedSubscriptionPopup(plan),
    );
    if (mounted) _selectedSubscription.value = null;
    if (resp != true) return;

    _recordBeganPayment(plan.planId);

    final userID = Matrix.of(context).client.userID!;
    final request = CheckoutRequest(userID: userID, planId: plan.planId);
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
    await launchUrlString(paymentLink, webOnlyWindowName: "_self");
  }

  @override
  Widget build(BuildContext context) {
    return SubscriptionStatusProvider(
      builder: (context, subscriptionStatusState) => ProductsProvider(
        builder: (context, productsState) => SettingsSubscriptionView(
          closeButton: widget.closeButton,
          subscriptionStatusState: subscriptionStatusState,
          productsState: productsState,
          onEnterDiscountCode: _onEnterDiscountCode,
          onTapSubscription: _onTapSubscription,
          selectedSubscription: _selectedSubscription,
        ),
      ),
    );
  }
}
