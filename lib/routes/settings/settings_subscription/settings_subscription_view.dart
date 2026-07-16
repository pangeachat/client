import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/enums/subscription_access_level_enum.dart';
import 'package:fluffychat/features/subscription/enums/subscription_type_enum.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_status_response.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/pro_features_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_options.dart';
import 'package:fluffychat/routes/settings/settings_subscription/user_subscription_plan_card.dart';

class SettingsSubscriptionView extends StatelessWidget {
  final Widget closeButton;
  final AsyncState<SubscriptionStatusResponse> subscriptionStatusState;
  final AsyncState<List<ProductPlan>> productsState;

  final Future<void> Function() onEnterDiscountCode;
  final Future<void> Function(ProductPlan) onTapSubscription;
  final ValueNotifier<ProductPlan?> selectedSubscription;

  const SettingsSubscriptionView({
    super.key,
    required this.closeButton,
    required this.subscriptionStatusState,
    required this.productsState,
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
          SafeArea(
            child: SingleChildScrollView(
              child: Container(
                alignment: Alignment.topCenter,
                child: Container(
                  padding: EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    bottom: 16.0,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  constraints: BoxConstraints(maxWidth: 400),
                  child: switch (subscriptionStatusState) {
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
                          ? products.firstWhereOrNull((p) => p.planId == planId)
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
                          switch (subscriptionStatus.accessLevel) {
                            SubscriptionAccessLevel.full => _FullAccessContent(
                              type: winning?.type,
                              subscriptionTitle:
                                  winning?.subscriptionTitle(l10n) ??
                                  l10n.currentSubscription,
                              paymentPeriodDescription: winning
                                  ?.paymentPeriodDescription(l10n),
                              priceDisplay:
                                  subscriptionPlan?.priceDisplay ??
                                  winning?.priceDisplay(l10n),
                              manageEligible: subscriptionStatus.manageEligible,
                              onTapSubscription: onTapSubscription,
                              productsState: productsState,
                              selectedSubscription: selectedSubscription,
                              onEnterDiscountCode: onEnterDiscountCode,
                            ),
                            SubscriptionAccessLevel.none => SubscriptionOptions(
                              onEnterDiscountCode: onEnterDiscountCode,
                              onTapSubscription: onTapSubscription,
                              productsState: productsState,
                              selectedSubscription: selectedSubscription,
                            ),
                          },
                        ],
                      );
                    }(),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullAccessContent extends StatelessWidget {
  final SubscriptionType? type;
  final String subscriptionTitle;
  final String? paymentPeriodDescription;
  final String? priceDisplay;
  final bool manageEligible;

  final Future<void> Function() onEnterDiscountCode;
  final Future<void> Function(ProductPlan) onTapSubscription;
  final AsyncState<List<ProductPlan>> productsState;
  final ValueNotifier<ProductPlan?> selectedSubscription;

  const _FullAccessContent({
    required this.type,
    required this.subscriptionTitle,
    this.paymentPeriodDescription,
    this.priceDisplay,
    this.manageEligible = false,
    required this.onEnterDiscountCode,
    required this.onTapSubscription,
    required this.productsState,
    required this.selectedSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    return Column(
      spacing: 20.0,
      children: [
        type == SubscriptionType.trial
            ? Text(
                paymentPeriodDescription ??
                    L10n.of(context).freeTrialDescription,
                style: isColumnMode
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleSmall,
              )
            : UserSubscriptionPlanCard(
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
        if (type == SubscriptionType.trial)
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
