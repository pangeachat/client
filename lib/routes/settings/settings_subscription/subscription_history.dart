import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/repo_v2/billing_portal_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/date_formatter.dart';
import 'package:fluffychat/routes/settings/settings_subscription/billing_portal_provider.dart';
import 'package:fluffychat/routes/settings/settings_subscription/invoice_history_builder.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_builder.dart';
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

  @override
  void initState() {
    super.initState();

    final userID = Matrix.of(context).client.userID!;
    _subscriptionStatusProvider.load(SubscriptionStatusRequest(userID: userID));
    _billingPortalProvider.load(BillingPortalRequest(userID: userID));
  }

  @override
  void dispose() {
    _subscriptionStatusProvider.dispose();
    _billingPortalProvider.dispose();
    super.dispose();
  }

  SubscriptionEntitlement? get _entitlement =>
      _subscriptionStatusProvider.response?.winningEntitlement;

  String? get _entitlementRef => _entitlement?.entitlementRef;

  DateTime? get _renewalDate => _entitlement?.endsAt;

  bool get _canCancelSubscription =>
      _entitlement?.cancelable == true &&
      _entitlementRef != null &&
      _subscriptionStatusProvider.response?.winning?.cancelAtPeriodEnd != true;

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
    final renewalDate = _renewalDate;
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
    final entitlementRef = _entitlementRef;
    if (entitlementRef == null) {
      throw "Cannot cancel subscription without entitlement";
    }

    final cancelResult = await SubscriptionCancelRepo.instance.get(
      SubscriptionCancelRequest(
        userID: Matrix.of(context).client.userID!,
        entitlementRef: entitlementRef,
      ),
    );

    final error = cancelResult.error;
    if (error != null) throw error;
  }

  @override
  Widget build(BuildContext context) {
    // V2 TODO - too many rebuilds
    return ValueListenableBuilder(
      valueListenable: _subscriptionStatusProvider.loader,
      builder: (context, subscriptionStatusState, _) => ValueListenableBuilder(
        valueListenable: _billingPortalProvider.loader,
        builder: (context, billingPortalState, _) => ProductsBuilder(
          builder: (context, productsState) => InvoiceHistoryBuilder(
            builder: (context, invoiceHistoryState) => SubscriptionHistoryView(
              closeButton: widget.closeButton,
              subscriptionStatusState: subscriptionStatusState,
              productsState: productsState,
              invoiceHistoryState: invoiceHistoryState,
              onCancelSubscription: _onCancelSubscription,
              canCancelSubscription: _canCancelSubscription,
            ),
          ),
        ),
      ),
    );
  }
}
