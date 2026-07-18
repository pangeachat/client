import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/dialog_wrapper.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_content.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_model.dart';
import 'package:fluffychat/routes/settings/settings_subscription/discount_code_view_title.dart';

class DiscountCodePopup extends StatelessWidget {
  final DiscountCodeViewModel viewModel;
  const DiscountCodePopup({super.key, required this.viewModel});

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
              CloseButton(onPressed: Navigator.of(context).pop),
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
            onSubscribe: Navigator.of(context).pop,
          ),
        ],
      ),
    );
  }
}
