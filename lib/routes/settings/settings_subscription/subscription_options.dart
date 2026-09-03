import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/widgets/subscription_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_option_card.dart';

class SubscriptionOptions extends StatelessWidget {
  final Future<void> Function() onEnterDiscountCode;
  final Future<void> Function(ProductPlan) onTapSubscription;

  final AsyncState<List<ProductPlan>> productsState;
  final ValueNotifier<ProductPlan?> selectedSubscription;

  const SubscriptionOptions({
    super.key,
    required this.onEnterDiscountCode,
    required this.onTapSubscription,
    required this.productsState,
    required this.selectedSubscription,
  });

  @override
  Widget build(BuildContext context) {
    return switch (productsState) {
      AsyncLoading() ||
      AsyncIdle() => Center(child: CircularProgressIndicator.adaptive()),
      AsyncError() => SizedBox.shrink(),
      AsyncLoaded(value: final plans) => SubscriptionOptionsInternal(
        plans,
        onEnterDiscountCode: onEnterDiscountCode,
        onTapSubscription: onTapSubscription,
        selectedSubscription: selectedSubscription,
      ),
    };
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

  /// Fixed width of a single plan chip.
  static const double _cardWidth = 150.0;

  /// Gap between plan chips, in both axes.
  static const double _spacing = 12.0;

  /// Width of a full row of chips, so the discount-code button can line up
  /// with the outer edges of the chips rather than with the pro-features box.
  double _rowWidth(double maxWidth) {
    final fit = ((maxWidth + _spacing) / (_cardWidth + _spacing)).floor();
    final perRow = fit.clamp(1, plans.isEmpty ? 1 : plans.length);
    return perRow * _cardWidth + (perRow - 1) * _spacing;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = _rowWidth(
          constraints.maxWidth.isFinite ? constraints.maxWidth : _cardWidth,
        );

        return Column(
          spacing: 12.0,
          children: [
            SubscriptionCard(
              child: Text(
                L10n.of(context).selectYourPlan,
                style:
                    (isColumnMode
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              width: rowWidth,
              child: ValueListenableBuilder(
                valueListenable: selectedSubscription,
                builder: (context, selectedPlan, _) => Wrap(
                  spacing: _spacing,
                  runSpacing: _spacing,
                  children: plans
                      .map(
                        (p) => SizedBox(
                          width: _cardWidth,
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
            ),
            SizedBox(
              width: rowWidth,
              child: ElevatedButton(
                onPressed: onEnterDiscountCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                ),
                child: Text(
                  L10n.of(context).enterDiscountCode,
                  textAlign: TextAlign.center,
                  style:
                      (isColumnMode
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.titleSmall)
                          ?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
