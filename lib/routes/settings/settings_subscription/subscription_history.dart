import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/enums/invoice_status_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_type_enum.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
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
            // subscriptionStatusState: subscriptionStatusState,
            // productsState: productsState,
            // invoiceHistoryState: invoiceHistoryState,
            subscriptionStatusState: AsyncLoaded(
              SubscriptionStatusResponse(
                accessLevel: SubscriptionAccessLevel.full,
                entitlementSource: 'rc',
                entitlements: [],
                manageEligible: true,
                trialClaimed: false,
                trialEligible: false,
                winning: SubscriptionWinning(
                  type: SubscriptionType.paid,
                  status: 'active',
                  cancelAtPeriodEnd: false,
                  provider: 'rc',
                  planId: 'month',
                ),
              ),
            ),
            productsState: AsyncLoaded([
              ProductPlan(
                planId: 'month',
                amount: 999,
                currency: 'usd',
                interval: '',
                intervalCount: 5,
              ),
            ]),
            invoiceHistoryState: AsyncLoaded([
              Invoice(
                id: '1',
                created: DateTime(2026, 7, 1),
                subtotal: 999,
                total: 0,
                amountPaid: 0,
                currency: 'usd',
                status: InvoiceStatus.paid,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
