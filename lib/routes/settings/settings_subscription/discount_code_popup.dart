import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/dialog_wrapper.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_content.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_model.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_title.dart';

class DiscountCodePopup extends StatelessWidget {
  final DiscountCodeViewModel viewModel;
  final AsyncState<List<ProductPlan>> productsState;
  const DiscountCodePopup({
    super.key,
    required this.viewModel,
    required this.productsState,
  });

  @override
  Widget build(BuildContext context) {
    return DialogWrapper(
      backgroundColor: Theme.of(context).colorScheme.surface,
      borderRadius: 16.0,
      side: BorderSide(color: AppConfig.goldByTheme(context)),
      maxHeight: 600.0,
      maxWidth: 375.0,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        spacing: 10.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CloseButton(onPressed: () => Navigator.of(context).pop()),
              Expanded(
                child: DiscountCodeViewTitle(
                  viewModel: viewModel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 40.0),
            ],
          ),
          DiscountCodeViewContent(
            viewModel: viewModel,
            productsState: productsState,
            onSubscribe: Navigator.of(context).pop,
          ),
        ],
      ),
    );
  }
}
