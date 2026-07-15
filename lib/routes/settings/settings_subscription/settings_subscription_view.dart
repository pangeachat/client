import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
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

  const SettingsSubscriptionView({
    super.key,
    required this.closeButton,
    required this.subscriptionStatusState,
    required this.productsState,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: closeButton),
        title: Text(
          L10n.of(context).subscriptionManagement,
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
            child: Container(
              alignment: Alignment.topCenter,
              padding: EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 300),
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
                      spacing: 16.0,
                      children: [
                        ProFeaturesCard(),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: switch (subscriptionStatus.accessLevel) {
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
                            ),
                            SubscriptionAccessLevel.none => _NoAccessContent(),
                          },
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

class _FullAccessContent extends StatelessWidget {
  final SubscriptionType? type;
  final String subscriptionTitle;
  final String? paymentPeriodDescription;
  final String? priceDisplay;
  final bool manageEligible;

  const _FullAccessContent({
    required this.type,
    required this.subscriptionTitle,
    this.paymentPeriodDescription,
    this.priceDisplay,
    this.manageEligible = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 12.0,
      children: [
        type == SubscriptionType.trial
            ? Text(
                paymentPeriodDescription ??
                    L10n.of(context).freeTrialDescription,
                style: theme.textTheme.titleLarge,
              )
            : UserSubscriptionPlanCard(
                subscriptionTitle: subscriptionTitle,
                priceDisplay: priceDisplay,
                paymentPeriodDescription: paymentPeriodDescription,
              ),
        if (manageEligible)
          Container(
            padding: EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 3.0),
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Row(
              children: [
                Expanded(child: Text(L10n.of(context).manage)),
                Icon(Icons.chevron_right),
              ],
            ),
          ),
        if (type == SubscriptionType.trial) _NoAccessContent(),
      ],
    );
  }
}

class _NoAccessContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsGeometry.symmetric(vertical: 16.0),
      child: Column(
        spacing: 12.0,
        children: [
          SubscriptionOptions(),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  L10n.of(context).enterDiscountCode,
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
