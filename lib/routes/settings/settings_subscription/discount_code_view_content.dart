import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_model.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_option_card.dart';
import 'package:fluffychat/widgets/matrix.dart';

class DiscountCodeViewContent extends StatelessWidget {
  final DiscountCodeViewModel viewModel;
  final void Function(CheckoutRequest) onSubscribe;
  const DiscountCodeViewContent({
    super.key,
    required this.viewModel,
    required this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputArea = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.disabledColor),
        borderRadius: BorderRadius.circular(32.0),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: viewModel.controller,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: L10n.of(context).enterDiscountCode,
              ),
            ),
          ),
          Container(
            width: 80.0,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.disabledColor)),
            ),
            child: ElevatedButton(
              onPressed: viewModel.validatePromoCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(32.0),
                    bottomRight: Radius.circular(32.0),
                  ),
                ),
              ),
              child: Text(L10n.of(context).apply),
            ),
          ),
        ],
      ),
    );

    final errorDisplay = Column(
      spacing: 10.0,
      children: [
        _DiscountCodeStatus(
          icon: Icons.error_outline,
          color: AppConfig.error,
          message: L10n.of(context).invalidDiscountCode,
        ),
        inputArea,
      ],
    );

    return ValueListenableBuilder(
      valueListenable: viewModel.loader,
      builder: (context, state, _) {
        return switch (state) {
          AsyncIdle() => inputArea,
          AsyncLoading() => LinearProgressIndicator(),
          AsyncError() => errorDisplay,
          AsyncLoaded(value: final response) => () {
            if (response.valid != true) return errorDisplay;

            final discountCopy = response.discountCopy;
            return Column(
              spacing: 10.0,
              children: [
                ValueListenableBuilder(
                  valueListenable: viewModel.productsNotifier,
                  builder: (context, productsState, _) =>
                      switch (productsState) {
                        AsyncLoading() ||
                        AsyncIdle() => LinearProgressIndicator(),
                        AsyncError() => _DiscountCodeStatus(
                          icon: Icons.error_outline,
                          color: AppConfig.error,
                          message: L10n.of(context).oopsSomethingWentWrong,
                        ),
                        AsyncLoaded(value: final plans) =>
                          ValueListenableBuilder(
                            valueListenable: viewModel.selectedSubscription,
                            builder: (context, selectedPlan, _) => Wrap(
                              spacing: 12.0,
                              runSpacing: 12.0,
                              children: plans
                                  .map(
                                    (p) => SizedBox(
                                      width: 160.0,
                                      child: SubscriptionOptionCard(
                                        p,
                                        onTap: () => viewModel
                                            .setSelectedSubscription(p),
                                        selected:
                                            selectedPlan != null &&
                                            p.planId == selectedPlan.planId,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      },
                ),
                if (discountCopy != null)
                  _DiscountCodeStatus(
                    icon: Icons.check,
                    color: AppConfig.success,
                    message: L10n.of(context).discountApplied(discountCopy),
                  ),
                ValueListenableBuilder(
                  valueListenable: viewModel.selectedSubscription,
                  builder: (context, selected, _) => ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                    ),
                    onPressed: selected != null
                        ? () => onSubscribe(
                            CheckoutRequest(
                              userID: Matrix.of(context).client.userID!,
                              planId: selected.planId,
                              promoCode: viewModel.controller.text.trim(),
                            ),
                          )
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Text(L10n.of(context).continueToSubscribe)],
                    ),
                  ),
                ),
              ],
            );
          }(),
        };
      },
    );
  }
}

/// An icon and message about the entered code, carrying its own surface so it
/// stays readable over the star backdrop.
class _DiscountCodeStatus extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _DiscountCodeStatus({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(32.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        spacing: 10.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24.0),
          Flexible(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
