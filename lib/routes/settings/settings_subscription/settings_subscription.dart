import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_popup.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_model.dart';
import 'package:fluffychat/routes/settings/settings_subscription/payment_page_mixin.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_builder.dart';
import 'package:fluffychat/routes/settings/settings_subscription/selected_subscription_popup.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription_view.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_status_provider.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SettingsSubscription extends StatefulWidget {
  final Widget closeButton;
  const SettingsSubscription({super.key, required this.closeButton});

  @override
  SettingsSubscriptionState createState() => SettingsSubscriptionState();
}

class SettingsSubscriptionState extends State<SettingsSubscription>
    with PaymentPageMixin {
  final SubscriptionStatusProvider _subscriptionStatusProvider =
      SubscriptionStatusProvider();

  final ValueNotifier<ProductPlan?> _selectedSubscription = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _loadSubscriptionStatus();
  }

  @override
  void dispose() {
    _subscriptionStatusProvider.dispose();
    _selectedSubscription.dispose();
    super.dispose();
  }

  Future<void> _loadSubscriptionStatus() => _subscriptionStatusProvider.load(
    SubscriptionStatusRequest(userID: Matrix.of(context).client.userID!),
  );

  Future<void> _onEnterDiscountCode() => FluffyThemes.isColumnMode(context)
      ? _showDiscountCodePopup()
      : _goToDiscountCodePage();

  Future<void> _goToDiscountCodePage() async => context.go(
    WorkspaceNav.openSettings(
      GoRouterState.of(context).uri,
      page: 'subscription/discount',
    ),
  );

  Future<void> _showDiscountCodePopup() async {
    final viewModel = DiscountCodeViewModel(
      userID: Matrix.of(context).client.userID!,
    );

    try {
      final resp = await showDialog<CheckoutRequest>(
        context: context,
        builder: (context) => DiscountCodePopup(viewModel: viewModel),
      );

      if (resp == null || !mounted) return;
      await processCheckoutRequest(resp);
    } finally {
      viewModel.dispose();
    }
  }

  Future<void> _onTapSubscription(ProductPlan plan) =>
      FluffyThemes.isColumnMode(context)
      ? _showSelectedSubscriptionPopup(plan)
      : _goToSelectedSubscriptionPage(plan);

  Future<void> _goToSelectedSubscriptionPage(ProductPlan plan) async =>
      context.go(
        WorkspaceNav.openSettings(
          GoRouterState.of(context).uri,
          page: 'subscription/selected',
          planId: plan.planId,
        ),
      );

  Future<void> _showSelectedSubscriptionPopup(ProductPlan plan) async {
    _selectedSubscription.value = plan;
    final resp = await showDialog<CheckoutRequest>(
      context: context,
      builder: (context) => SelectedSubscriptionPopup(plan),
    );
    if (mounted) _selectedSubscription.value = null;
    if (resp == null || !mounted) return;
    await processCheckoutRequest(resp);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _subscriptionStatusProvider.loader,
      builder: (context, subscriptionStatusState, _) => ProductsBuilder(
        builder: (context, productsState) => SettingsSubscriptionView(
          closeButton: widget.closeButton,
          subscriptionStatusState: subscriptionStatusState,
          productsState: productsState,
          reloadStatus: _loadSubscriptionStatus,
          onEnterDiscountCode: _onEnterDiscountCode,
          onTapSubscription: _onTapSubscription,
          selectedSubscription: _selectedSubscription,
        ),
      ),
    );
  }
}
