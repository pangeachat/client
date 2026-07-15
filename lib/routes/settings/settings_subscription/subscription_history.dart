import 'package:flutter/material.dart';

import 'package:fluffychat/routes/settings/settings_subscription/invoice_history_provider.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_provider.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_history_view.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_status_provider.dart';

class SubscriptionHistory extends StatelessWidget {
  final Widget closeButton;
  const SubscriptionHistory({super.key, required this.closeButton});

  @override
  Widget build(BuildContext context) {
    return SubscriptionStatusProvider(
      builder: (context, subscriptionStatusState) => ProductsProvider(
        builder: (context, productsState) => InvoiceHistoryProvider(
          builder: (context, invoiceHistoryState) => SubscriptionHistoryView(
            closeButton: closeButton,
            subscriptionStatusState: subscriptionStatusState,
            productsState: productsState,
            invoiceHistoryState: invoiceHistoryState,
          ),
        ),
      ),
    );
  }
}
