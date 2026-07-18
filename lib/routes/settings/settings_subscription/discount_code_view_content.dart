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
        Row(
          spacing: 10.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppConfig.error, size: 24.0),
            Text(
              L10n.of(context).invalidDiscountCode,
              style: TextStyle(color: AppConfig.error),
            ),
          ],
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
                        AsyncError() => Row(
                          spacing: 10.0,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: AppConfig.error,
                              size: 24.0,
                            ),
                            Text(
                              L10n.of(context).oopsSomethingWentWrong,
                              style: TextStyle(color: AppConfig.error),
                            ),
                          ],
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
                Row(
                  spacing: 10.0,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, color: AppConfig.success, size: 24.0),
                    if (discountCopy != null)
                      Text(
                        L10n.of(context).discountApplied(discountCopy),
                        style: TextStyle(color: AppConfig.success),
                      ),
                  ],
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
