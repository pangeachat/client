import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:highlight/languages/go.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_cancel_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_request.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/invoice_history_builder.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_builder.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_history_view.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_status_builder.dart';
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
  Future<void> _onCancelSubscription() async {
    final resp = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: L10n.of(context).cancelDescriptionDialogWarning(),
      isDestructive: true,
    );

    if (resp != OkCancelResult.ok) return;

    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final cancelResult = await SubscriptionCancelRepo.instance.get(
          SubscriptionCancelRequest(
            userID: Matrix.of(context).client.userID!,
            entitlementRef: entitlementRef,
          ),
        );

        final error = cancelResult.error;
        if (error != null) throw error;
      },
    );

    if (result.isError) return;
    if (mounted) {
      context.go(
        WorkspaceNav.openSettings(
          GoRouterState.of(context).uri,
          page: 'subscription',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubscriptionStatusBuilder(
      builder: (context, subscriptionStatusState) => ProductsBuilder(
        builder: (context, productsState) => InvoiceHistoryBuilder(
          builder: (context, invoiceHistoryState) => SubscriptionHistoryView(
            closeButton: widget.closeButton,
            subscriptionStatusState: subscriptionStatusState,
            productsState: productsState,
            invoiceHistoryState: invoiceHistoryState,
            onCancelSubscription: _onCancelSubscription,
          ),
        ),
      ),
    );
  }
}
