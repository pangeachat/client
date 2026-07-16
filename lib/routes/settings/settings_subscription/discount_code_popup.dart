import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:async/async.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/checkout_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_response.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_option_card.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

typedef _ValidationLoader =
    ValueNotifier<AsyncState<ValidatePromoCodeResponse>>;

class DiscountCodePopup extends StatefulWidget {
  final Future<Result<ValidatePromoCodeResponse>> Function(String) validateCode;
  final AsyncState<List<ProductPlan>> productsState;
  const DiscountCodePopup({
    super.key,
    required this.validateCode,
    required this.productsState,
  });

  @override
  DiscountCodePopupState createState() => DiscountCodePopupState();
}

class DiscountCodePopupState extends State<DiscountCodePopup> {
  final TextEditingController _controller = TextEditingController();
  final _ValidationLoader _loader = _ValidationLoader(AsyncIdle());
  final ValueNotifier<ProductPlan?> _selectedSubscription = ValueNotifier(null);

  int _generation = 0;

  @override
  void dispose() {
    _controller.dispose();
    _loader.dispose();
    _selectedSubscription.dispose();
    super.dispose();
  }

  void _setSelectedSubscription(ProductPlan plan) =>
      _selectedSubscription.value = plan;

  void _setLoaderValue(
    int generation,
    AsyncState<ValidatePromoCodeResponse> value,
  ) {
    if (mounted && _generation == generation) {
      _loader.value = value;
    }
  }

  Future<void> _validatePromoCode() async {
    _generation++;
    final generation = _generation;
    _setLoaderValue(generation, AsyncLoading());

    final result = await widget.validateCode(_controller.text.trim());
    final response = result.result;
    _setLoaderValue(
      generation,
      response != null
          ? AsyncLoaded(response)
          : AsyncError(result.error ?? "Failed to validate promo code"),
    );
  }

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
              controller: _controller,
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
              onPressed: _validatePromoCode,
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

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: BorderSide(color: AppConfig.goldByTheme(context)),
        ),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600.0, maxWidth: 375.0),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            spacing: 10.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CloseButton(onPressed: () => Navigator.of(context).pop()),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: _loader,
                      builder: (context, state, _) => Text(
                        switch (state) {
                          AsyncLoaded() => L10n.of(context).selectDiscountPlan,
                          _ => L10n.of(context).enterDiscountCode,
                        },
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  SizedBox(width: 40.0),
                ],
              ),
              ValueListenableBuilder(
                valueListenable: _loader,
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
                          switch (widget.productsState) {
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
                                valueListenable: _selectedSubscription,
                                builder: (context, selectedPlan, _) => Wrap(
                                  spacing: 12.0,
                                  runSpacing: 12.0,
                                  children: plans
                                      .map(
                                        (p) => SizedBox(
                                          width: 160.0,
                                          child: SubscriptionOptionCard(
                                            p,
                                            onTap: () =>
                                                _setSelectedSubscription(p),
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
                          Row(
                            spacing: 10.0,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check,
                                color: AppConfig.success,
                                size: 24.0,
                              ),
                              if (discountCopy != null)
                                Text(
                                  L10n.of(
                                    context,
                                  ).discountApplied(discountCopy),
                                  style: TextStyle(color: AppConfig.success),
                                ),
                            ],
                          ),
                          ValueListenableBuilder(
                            valueListenable: _selectedSubscription,
                            builder: (context, selected, _) => ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                              ),
                              onPressed: selected != null
                                  ? () => Navigator.of(context).pop(
                                      CheckoutRequest(
                                        userID: Matrix.of(
                                          context,
                                        ).client.userID!,
                                        planId: selected.planId,
                                        promoCode: _controller.text.trim(),
                                      ),
                                    )
                                  : null,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(L10n.of(context).continueToSubscribe),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }(),
                  };
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
