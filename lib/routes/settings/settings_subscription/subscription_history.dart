import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/repo_v2/billing_portal_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/date_formatter.dart';
import 'package:fluffychat/routes/settings/settings_subscription/billing_portal_provider.dart';
import 'package:fluffychat/routes/settings/settings_subscription/invoice_history_provider.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_provider.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_history_view.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_status_provider.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionHistory extends StatefulWidget {
  final Widget closeButton;
  const SubscriptionHistory({super.key, required this.closeButton});

  @override
  SubscriptionHistoryState createState() => SubscriptionHistoryState();
}

class SubscriptionHistoryState extends State<SubscriptionHistory> {
  final _subscriptionStatusProvider = SubscriptionStatusProvider();
  final _billingPortalProvider = BillingPortalProvider();
  final _productsProvider = ProductsProvider();
  final _invoiceHistoryProvider = InvoiceHistoryProvider();

  final ValueNotifier<ProductPlan?> _subscriptionPlanNotifier = ValueNotifier(
    null,
  );

  final ValueNotifier<bool> _canCancelNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _canManageNotifier = ValueNotifier(false);

  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_loaded) return;
    _loaded = true;

    _productsProvider.loader.addListener(_updateSubscriptionPlan);
    _subscriptionStatusProvider.loader.addListener(_updateSubscriptionPlan);
    _subscriptionStatusProvider.loader.addListener(_updateManagementNotifiers);
    _billingPortalProvider.loader.addListener(_updateManagementNotifiers);

    final userID = Matrix.of(context).client.userID!;
    _subscriptionStatusProvider.load(SubscriptionStatusRequest(userID: userID));
    _billingPortalProvider.load(BillingPortalRequest(userID: userID));
    _productsProvider.load(ProductsRequest(userID: userID));
    _invoiceHistoryProvider.load(InvoiceHistoryRequest(userID: userID));
  }

  @override
  void dispose() {
    _productsProvider.loader.removeListener(_updateSubscriptionPlan);
    _subscriptionStatusProvider.loader.removeListener(_updateSubscriptionPlan);
    _subscriptionStatusProvider.loader.removeListener(
      _updateManagementNotifiers,
    );
    _billingPortalProvider.loader.removeListener(_updateManagementNotifiers);

    _subscriptionStatusProvider.dispose();
    _billingPortalProvider.dispose();
    _productsProvider.dispose();
    _invoiceHistoryProvider.dispose();

    _subscriptionPlanNotifier.dispose();
    _canCancelNotifier.dispose();
    _canManageNotifier.dispose();
    super.dispose();
  }

  String? get _billingPortal => _billingPortalProvider.response?.url;

  bool get _canCancelSubscription => _cancelableEntitlement != null;

  bool get _canManageSubscription =>
      _subscriptionStatusProvider.response?.manageEligible == true &&
      _billingPortal != null;

  SubscriptionEntitlement? get _cancelableEntitlement =>
      _subscriptionStatusProvider.response?.cancelableEntitlement;

  void _updateSubscriptionPlan() {
    final products = _productsProvider.response ?? [];
    final planId = _subscriptionStatusProvider.response?.winning?.planId;
    if (planId == null) {
      _subscriptionPlanNotifier.value = null;
      return;
    }

    final subscriptionPlan = products.firstWhereOrNull(
      (p) => p.planId == planId,
    );
    _subscriptionPlanNotifier.value = subscriptionPlan;
  }

  void _updateManagementNotifiers() {
    _canCancelNotifier.value = _canCancelSubscription;
    _canManageNotifier.value = _canManageSubscription;
  }

  Future<void> _onCancelSubscription() async {
    if (!await _confirmCancelSubscription()) return;

    final result = await showFutureLoadingDialog(
      context: context,
      future: _cancelSubscription,
    );
    if (result.isError) return;

    await SubscriptionStatusRepo.instance.clearCache();
    if (mounted) {
      context.go(
        WorkspaceNav.openSettings(
          GoRouterState.of(context).uri,
          page: 'subscription',
        ),
      );
    }
  }

  Future<bool> _confirmCancelSubscription() async {
    final renewalDate = _cancelableEntitlement?.endsAt;
    final resp = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: renewalDate != null
          ? L10n.of(context).cancelDescriptionWithRenewalDate(
              DateFormatter.format(renewalDate),
            )
          : L10n.of(context).cancelDescriptionWithoutRenewalDate,
      isDestructive: true,
    );
    return resp == OkCancelResult.ok;
  }

  Future<void> _cancelSubscription() async {
    final entitlementRef = _cancelableEntitlement?.entitlementRef;
    if (entitlementRef == null) {
      throw "Cannot cancel subscription without entitlement";
    }

    final cancelResult = await SubscriptionCancelRepo.instance
        .cancelSubscription(
          SubscriptionCancelRequest(
            userID: Matrix.of(context).client.userID!,
            entitlementRef: entitlementRef,
          ),
        );

    final error = cancelResult.error;
    if (error != null) throw error;
  }

  Future<void> _onManageSubscription() =>
      showFutureLoadingDialog(context: context, future: _manageSubscription);

  Future<void> _manageSubscription() async {
    final billingPortal = _billingPortal;
    if (billingPortal == null) {
      throw "Cannot manage subscription without billing portal link";
    }

    await launchUrlString(billingPortal);
  }

  @override
  Widget build(BuildContext context) => SubscriptionHistoryView(
    closeButton: widget.closeButton,
    subscriptionStatusNotifier: _subscriptionStatusProvider.loader,
    subscriptionPlanNotifier: _subscriptionPlanNotifier,
    invoiceHistoryNotifier: _invoiceHistoryProvider.loader,
    canCancelSubscriptionNotifier: _canCancelNotifier,
    onCancelSubscription: _onCancelSubscription,
    canManageSubscriptionNotifier: _canManageNotifier,
    onManageSubscription: _onManageSubscription,
  );
}
