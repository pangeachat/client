import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/user_subscription_plan_card.dart';

class SubscriptionHistoryView extends StatelessWidget {
  final Widget closeButton;
  final AsyncState<SubscriptionStatusResponse> subscriptionStatusState;
  final AsyncState<List<ProductPlan>> productsState;
  final AsyncState<List<Invoice>> invoiceHistoryState;
  final Future<void> Function() onCancelSubscription;
  final bool canCancelSubscription;

  const SubscriptionHistoryView({
    super.key,
    required this.closeButton,
    required this.subscriptionStatusState,
    required this.productsState,
    required this.invoiceHistoryState,
    required this.onCancelSubscription,
    required this.canCancelSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: Center(child: closeButton),
        title: Text(
          L10n.of(context).subscriptionHistory,
          style: FluffyThemes.isColumnMode(context)
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: Stack(
        children: [
          SizedBox.expand(
            child: ExcludeSemantics(
              child: CachedNetworkImage(
                imageUrl:
                    "${AppConfig.assetsBaseURL}/${SubscriptionConstants.starBackground}",
                fit: BoxFit.cover,
                alignment: Alignment.center,
                placeholder: (context, url) => const SizedBox(),
                errorWidget: (context, url, error) => const SizedBox(),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Container(
                alignment: Alignment.topCenter,
                padding: EdgeInsets.all(32),
                child: Container(
                  padding: EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  constraints: BoxConstraints(maxWidth: 400),
                  child: Column(
                    spacing: 16.0,
                    children: [
                      switch (subscriptionStatusState) {
                        AsyncLoading() || AsyncIdle() => Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                        AsyncError() => SizedBox.shrink(),
                        AsyncLoaded(value: final subscriptionStatus) => () {
                          final winning = subscriptionStatus.winning;

                          final products = switch (productsState) {
                            AsyncLoaded(value: final products) => products,
                            _ => const <ProductPlan>[],
                          };

                          final planId = subscriptionStatus.winning?.planId;
                          final subscriptionPlan = planId != null
                              ? products.firstWhereOrNull(
                                  (p) => p.planId == planId,
                                )
                              : null;

                          return UserSubscriptionPlanCard(
                            subscriptionTitle:
                                winning?.subscriptionTitle(l10n) ??
                                l10n.currentSubscription,
                            paymentPeriodDescription: winning
                                ?.paymentPeriodDescription(l10n),
                            priceDisplay:
                                subscriptionPlan?.priceDisplay ??
                                winning?.priceDisplay(l10n),
                            showCancel: canCancelSubscription,
                            onCancel: onCancelSubscription,
                          );
                        }(),
                      },
                      switch (invoiceHistoryState) {
                        AsyncLoading() || AsyncIdle() => Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                        AsyncError() => SizedBox.shrink(),
                        AsyncLoaded(value: final invoices) =>
                          invoices.isEmpty
                              ? Text(L10n.of(context).noPaymentHistoryFound)
                              : _InvoiceHistoryList(invoices),
                      },
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceHistoryList extends StatelessWidget {
  final List<Invoice> invoices;
  const _InvoiceHistoryList(this.invoices);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatter = DateFormat('yyyy-MM-dd');

    return FrameContainer(
      title: L10n.of(context).history,
      frameColor: theme.colorScheme.primaryContainer,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      padding: EdgeInsets.all(8.0),
      titlePadding: EdgeInsetsGeometry.symmetric(
        vertical: 8.0,
        horizontal: 12.0,
      ),
      borderRadius: 12.0,
      expandable: true,
      initiallyExpanded: false,
      child: Column(
        children: [
          ...invoices.map(
            (invoice) => Padding(
              padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              child: Row(
                spacing: 4.0,
                children: [
                  Expanded(
                    child: Text(
                      formatter.format(invoice.created),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (invoice.showSubtotal)
                    Text(
                      invoice.subtotalDisplay,
                      style: theme.textTheme.labelSmall?.copyWith(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    invoice.totalDisplay,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
