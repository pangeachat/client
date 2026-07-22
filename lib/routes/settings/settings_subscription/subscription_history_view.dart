import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/date_formatter.dart';
import 'package:fluffychat/routes/settings/settings_subscription/user_subscription_plan_card.dart';

class SubscriptionHistoryView extends StatelessWidget {
  final Widget closeButton;
  final ValueNotifier<SubscriptionState> subscriptionStatusNotifier;
  final ValueNotifier<AsyncState<List<Invoice>>> invoiceHistoryNotifier;
  final ValueNotifier<ProductPlan?> subscriptionPlanNotifier;

  final ValueNotifier<bool> canCancelSubscriptionNotifier;
  final Future<void> Function()? onCancelSubscription;

  final ValueNotifier<bool> canManageSubscriptionNotifier;
  final Future<void> Function()? onManageSubscription;

  const SubscriptionHistoryView({
    super.key,
    required this.closeButton,
    required this.subscriptionStatusNotifier,
    required this.subscriptionPlanNotifier,
    required this.invoiceHistoryNotifier,
    required this.canCancelSubscriptionNotifier,
    required this.onCancelSubscription,
    required this.canManageSubscriptionNotifier,
    required this.onManageSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return Scaffold(
      appBar: AppBar(
        leading: Center(child: closeButton),
        title: Text(
          L10n.of(context).subscriptionHistory,
          style: isColumnMode
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
                      ValueListenableBuilder(
                        valueListenable: subscriptionStatusNotifier,
                        builder: (context, subscriptionStatusState, _) =>
                            switch (subscriptionStatusState) {
                              SubscriptionLoading() => Center(
                                child: CircularProgressIndicator.adaptive(),
                              ),
                              SubscriptionError() => SizedBox.shrink(),
                              SubscriptionActive(
                                response: final subscriptionStatus,
                              ) ||
                              SubscriptionInactive(
                                response: final subscriptionStatus,
                              ) => ValueListenableBuilder(
                                valueListenable: subscriptionPlanNotifier,
                                builder: (context, subscriptionPlan, _) {
                                  final displayEntitlement =
                                      subscriptionStatus.cardDisplayEntitlement;

                                  final activeTrial =
                                      subscriptionStatus.activeTrial;

                                  final trialDescription = activeTrial
                                      ?.paymentPeriodDescription(l10n);

                                  return Column(
                                    spacing: 20.0,
                                    children: [
                                      if (activeTrial != null &&
                                          trialDescription != null)
                                        Text(
                                          trialDescription,
                                          style: isColumnMode
                                              ? theme.textTheme.titleMedium
                                              : theme.textTheme.titleSmall,
                                        ),
                                      UserSubscriptionPlanCard(
                                        subscriptionTitle:
                                            displayEntitlement
                                                ?.subscriptionTitle(l10n) ??
                                            l10n.currentSubscription,
                                        paymentPeriodDescription:
                                            displayEntitlement
                                                ?.paymentPeriodDescription(
                                                  l10n,
                                                ),
                                        priceDisplay:
                                            subscriptionPlan?.priceDisplay ??
                                            displayEntitlement?.priceDisplay(
                                              l10n,
                                            ),
                                        showCancel: true,
                                        canCancelNotifier:
                                            canCancelSubscriptionNotifier,
                                        onCancel: onCancelSubscription,
                                        showManage: true,
                                        canManageNotifier:
                                            canManageSubscriptionNotifier,
                                        onManage: onManageSubscription,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            },
                      ),
                      ValueListenableBuilder(
                        valueListenable: invoiceHistoryNotifier,
                        builder: (context, invoiceHistoryState, _) =>
                            switch (invoiceHistoryState) {
                              AsyncLoading() || AsyncIdle() => Center(
                                child: CircularProgressIndicator.adaptive(),
                              ),
                              AsyncError() => SizedBox.shrink(),
                              AsyncLoaded(value: final invoices) =>
                                invoices.isEmpty
                                    ? Text(
                                        L10n.of(context).noPaymentHistoryFound,
                                      )
                                    : _InvoiceHistoryList(invoices),
                            },
                      ),
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
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return FrameContainer(
      title: L10n.of(context).history,
      titleStyle:
          (isColumnMode
                  ? theme.textTheme.titleLarge
                  : theme.textTheme.titleMedium)
              ?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
      titlePadding: isColumnMode
          ? const EdgeInsets.all(12.0)
          : const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
      frameColor: theme.colorScheme.primaryContainer,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      padding: EdgeInsets.all(8.0),
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
                      DateFormatter.format(invoice.created),
                      style: isColumnMode
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleSmall,
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
                    style:
                        (isColumnMode
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.titleSmall)
                            ?.copyWith(fontWeight: FontWeight.bold),
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
