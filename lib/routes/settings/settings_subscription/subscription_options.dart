import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/products_provider.dart';

class SubscriptionOptions extends StatelessWidget {
  const SubscriptionOptions({super.key});

  @override
  Widget build(BuildContext context) {
    return ProductsProvider(
      builder: (context, state) => switch (state) {
        AsyncLoading() ||
        AsyncIdle() => Center(child: CircularProgressIndicator.adaptive()),
        AsyncError() => SizedBox.shrink(),
        AsyncLoaded(value: final plans) => SubscriptionOptionsInternal(plans),
      },
    );
  }
}

class SubscriptionOptionsInternal extends StatelessWidget {
  final List<ProductPlan> plans;
  const SubscriptionOptionsInternal(this.plans, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 12.0,
      children: [
        Text(
          L10n.of(context).selectYourPlan,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          spacing: 12.0,
          children: plans
              .map((p) => Expanded(child: _SubscriptionOptionCard(p)))
              .toList(),
        ),
      ],
    );
  }
}

class _SubscriptionOptionCard extends StatelessWidget {
  final ProductPlan plan;
  const _SubscriptionOptionCard(this.plan);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return FrameContainer(
      title: plan.duration.cardTitle(l10n),
      frameColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onPrimary,
      padding: EdgeInsets.all(8.0),
      titlePadding: EdgeInsetsGeometry.symmetric(
        vertical: 8.0,
        horizontal: 2.0,
      ),
      borderRadius: 12.0,
      child: Column(
        spacing: 8.0,
        children: [
          Text(
            plan.duration.copy(l10n),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(plan.priceDisplay, style: theme.textTheme.headlineMedium),
        ],
      ),
    );
  }
}
