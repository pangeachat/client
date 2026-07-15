import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_builder.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_option_card.dart';

class SubscriptionOptions extends StatelessWidget {
  final Future<void> Function() onEnterDiscountCode;
  final Future<void> Function(ProductPlan) onTapSubscription;
  final ValueNotifier<ProductPlan?> selectedSubscription;
  const SubscriptionOptions({
    super.key,
    required this.onEnterDiscountCode,
    required this.onTapSubscription,
    required this.selectedSubscription,
  });

  @override
  Widget build(BuildContext context) {
    return ProductsBuilder(
      builder: (context, state) => switch (state) {
        AsyncLoading() ||
        AsyncIdle() => Center(child: CircularProgressIndicator.adaptive()),
        AsyncError() => SizedBox.shrink(),
        AsyncLoaded(value: final plans) => SubscriptionOptionsInternal(
          plans,
          onEnterDiscountCode: onEnterDiscountCode,
          onTapSubscription: onTapSubscription,
          selectedSubscription: selectedSubscription,
        ),
      },
    );
  }
}

class SubscriptionOptionsInternal extends StatelessWidget {
  final List<ProductPlan> plans;
  final Future<void> Function() onEnterDiscountCode;
  final Future<void> Function(ProductPlan) onTapSubscription;
  final ValueNotifier<ProductPlan?> selectedSubscription;
  const SubscriptionOptionsInternal(
    this.plans, {
    super.key,
    required this.onEnterDiscountCode,
    required this.onTapSubscription,
    required this.selectedSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 12.0,
      children: [
        Text(
          L10n.of(context).selectYourPlan,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        ValueListenableBuilder(
          valueListenable: selectedSubscription,
          builder: (context, selectedPlan, _) => Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            children: plans
                .map(
                  (p) => SizedBox(
                    width: 160.0,
                    child: SubscriptionOptionCard(
                      p,
                      onTap: () => onTapSubscription(p),
                      selected:
                          selectedPlan != null &&
                          p.planId == selectedPlan.planId,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        ElevatedButton(
          onPressed: onEnterDiscountCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                L10n.of(context).enterDiscountCode,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
