import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/pro_features_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_options.dart';
import 'package:fluffychat/routes/settings/settings_subscription/user_subscription_plan_card.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';

class SettingsSubscriptionView extends StatelessWidget {
  final Widget closeButton;
  final AsyncState<SubscriptionStatusResponse> subscriptionStatusState;
  final AsyncState<List<ProductPlan>> productsState;

  final VoidCallback reloadStatus;
  final Future<void> Function() onEnterDiscountCode;
  final Future<void> Function(ProductPlan) onTapSubscription;
  final ValueNotifier<ProductPlan?> selectedSubscription;

  const SettingsSubscriptionView({
    super.key,
    required this.closeButton,
    required this.subscriptionStatusState,
    required this.productsState,
    required this.reloadStatus,
    required this.onEnterDiscountCode,
    required this.onTapSubscription,
    required this.selectedSubscription,
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
          L10n.of(context).subscriptionManagement,
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
          SingleChildScrollView(
            child: Container(
              alignment: Alignment.topCenter,
              child: Container(
                padding: EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24.0),
                ),
                constraints: BoxConstraints(maxWidth: 400),
                child: switch (subscriptionStatusState) {
                  AsyncLoading() || AsyncIdle() => Center(
                    child: CircularProgressIndicator.adaptive(),
                  ),
                  AsyncError(error: final error) => Center(
                    child: Row(
                      spacing: 8.0,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ErrorIndicator(
                          message: error.toLocalizedString(context),
                        ),
                        IconButton(
                          tooltip: L10n.of(context).refresh,
                          icon: Icon(Icons.refresh),
                          onPressed: reloadStatus,
                        ),
                      ],
                    ),
                  ),
                  AsyncLoaded(value: final subscriptionStatus) => () {
                    final products = switch (productsState) {
                      AsyncLoaded(value: final products) => products,
                      _ => const <ProductPlan>[],
                    };

                    final activeTrial = subscriptionStatus.activeTrial;

                    final displayEntitlement =
                        subscriptionStatus.cardDisplayEntitlement;

                    final displayPlan = displayEntitlement?.planId != null
                        ? products.firstWhereOrNull(
                            (p) => p.planId == displayEntitlement?.planId,
                          )
                        : null;

                    return Column(
                      spacing: 20.0,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ProFeaturesCard(
                          titlePadding: isColumnMode
                              ? const EdgeInsets.all(12.0)
                              : const EdgeInsets.all(4.0),
                          padding: isColumnMode
                              ? const EdgeInsets.all(24)
                              : const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 24,
                                ),
                        ),
                        subscriptionStatus.isActive
                            ? FullAccessContent(
                                showTrialInfo: activeTrial != null,
                                trialDescription: activeTrial
                                    ?.paymentPeriodDescription(l10n),
                                subscriptionTitle:
                                    displayEntitlement?.subscriptionTitle(
                                      l10n,
                                    ) ??
                                    l10n.currentSubscription,
                                paymentPeriodDescription: displayEntitlement
                                    ?.paymentPeriodDescription(l10n),
                                priceDisplay:
                                    displayPlan?.priceDisplay ??
                                    displayEntitlement?.priceDisplay(l10n),
                                manageEligible:
                                    subscriptionStatus.manageEligible,
                                onTapSubscription: onTapSubscription,
                                productsState: productsState,
                                selectedSubscription: selectedSubscription,
                                onEnterDiscountCode: onEnterDiscountCode,
                              )
                            : SubscriptionOptions(
                                onEnterDiscountCode: onEnterDiscountCode,
                                onTapSubscription: onTapSubscription,
                                productsState: productsState,
                                selectedSubscription: selectedSubscription,
                              ),
                      ],
                    );
                  }(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FullAccessContent extends StatelessWidget {
  final bool showTrialInfo;
  final String? trialDescription;

  final bool showSubscriptionCard;
  final String? subscriptionTitle;
  final String? paymentPeriodDescription;
  final String? priceDisplay;

  final bool manageEligible;
  final bool showSubscriptionOptions;

  final Future<void> Function() onEnterDiscountCode;
  final Future<void> Function(ProductPlan) onTapSubscription;
  final AsyncState<List<ProductPlan>> productsState;
  final ValueNotifier<ProductPlan?> selectedSubscription;

  const FullAccessContent({
    super.key,
    this.showTrialInfo = false,
    this.trialDescription,
    this.showSubscriptionCard = true,
    this.subscriptionTitle,
    this.paymentPeriodDescription,
    this.priceDisplay,
    this.manageEligible = false,
    this.showSubscriptionOptions = false,
    required this.onEnterDiscountCode,
    required this.onTapSubscription,
    required this.productsState,
    required this.selectedSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    final subscriptionTitle = this.subscriptionTitle;
    final trialDescription = this.trialDescription;

    return Column(
      spacing: 20.0,
      children: [
        if (showTrialInfo && trialDescription != null)
          Text(
            trialDescription,
            style: isColumnMode
                ? theme.textTheme.titleMedium
                : theme.textTheme.titleSmall,
          ),
        if (showSubscriptionCard && subscriptionTitle != null)
          UserSubscriptionPlanCard(
            subscriptionTitle: subscriptionTitle,
            priceDisplay: priceDisplay,
            paymentPeriodDescription: paymentPeriodDescription,
          ),
        if (manageEligible)
          InkWell(
            onTap: () => context.go(
              WorkspaceNav.openSettings(
                GoRouterState.of(context).uri,
                page: 'subscription/history',
              ),
            ),
            borderRadius: BorderRadius.circular(12.0),
            child: Container(
              padding: EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.primaryContainer,
                  width: 3.0,
                ),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      L10n.of(context).manage,
                      style: isColumnMode
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleSmall,
                    ),
                  ),
                  Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        if (showSubscriptionOptions)
          SubscriptionOptions(
            onEnterDiscountCode: onEnterDiscountCode,
            onTapSubscription: onTapSubscription,
            productsState: productsState,
            selectedSubscription: selectedSubscription,
          ),
      ],
    );
  }
}
