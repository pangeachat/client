import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_provider.dart';

class SubscriptionOptions extends StatelessWidget {
  final Future<void> Function(ProductPlan) onTapSubscription;
  final ValueNotifier<ProductPlan?> selectedSubscription;
  const SubscriptionOptions({
    super.key,
    required this.onTapSubscription,
    required this.selectedSubscription,
  });

  @override
  Widget build(BuildContext context) {
    return ProductsProvider(
      builder: (context, state) => switch (state) {
        AsyncLoading() ||
        AsyncIdle() => Center(child: CircularProgressIndicator.adaptive()),
        AsyncError() => SizedBox.shrink(),
        AsyncLoaded(value: final plans) => SubscriptionOptionsInternal(
          plans,
          onTapSubscription: onTapSubscription,
          selectedSubscription: selectedSubscription,
        ),
      },
    );
  }
}

class SubscriptionOptionsInternal extends StatelessWidget {
  final List<ProductPlan> plans;
  final Future<void> Function(ProductPlan) onTapSubscription;
  final ValueNotifier<ProductPlan?> selectedSubscription;
  const SubscriptionOptionsInternal(
    this.plans, {
    super.key,
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
                    child: _SubscriptionOptionCard(
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
          onPressed: () {},
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

class _SubscriptionOptionCard extends StatelessWidget {
  final ProductPlan plan;
  final VoidCallback onTap;
  final bool selected;
  const _SubscriptionOptionCard(
    this.plan, {
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: FrameContainer(
        title: plan.duration.cardTitle(l10n),
        frameColor: selected
            ? AppConfig.goldByTheme(context)
            : theme.colorScheme.primaryContainer,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: selected
            ? (theme.brightness == Brightness.light
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.surface)
            : theme.colorScheme.onPrimaryContainer,
        padding: EdgeInsets.all(8.0),
        titlePadding: EdgeInsetsGeometry.symmetric(
          vertical: 8.0,
          horizontal: 2.0,
        ),
        borderRadius: 12.0,
        titleStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        child: Column(
          spacing: 8.0,
          children: [
            Text(
              plan.duration.copy(l10n),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(plan.priceDisplay, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
