import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/features/subscription/repo_v2/checkout_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_management_repo.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
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

  Future<void> _onTapSubscription(ProductPlan plan) async {
    _selectedSubscription.value = plan;
    final resp = await showDialog(
      context: context,
      builder: (context) => SelectedSubscriptionPopup(plan),
    );
    if (mounted) _selectedSubscription.value = null;
    if (resp != true) return;

    try {
      GoogleAnalytics.beginPurchaseSubscription(plan.planId, null, context);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"plan_id": plan.planId});
    }

    final userID = Matrix.of(context).client.userID!;
    final checkoutResult = await showFutureLoadingDialog<String>(
      context: context,
      future: () async {
        final checkoutResult = await CheckoutRepo.instance.getPaymentLink(
          CheckoutRequest(userID: userID, planId: plan.planId),
        );

        final checkoutResponse = checkoutResult.result;
        if (checkoutResponse == null) {
          throw checkoutResult.asError ?? "Failed to checkout";
        }

        return checkoutResponse;
      },
    );

    final paymentLink = checkoutResult.result;
    if (paymentLink == null) return;

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
          onTapSubscription: _onTapSubscription,
          selectedSubscription: _selectedSubscription,
        ),
      ),
    );
  }
}
