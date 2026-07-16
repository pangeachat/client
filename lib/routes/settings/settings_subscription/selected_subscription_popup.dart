import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/pangea/common/widgets/dialog_wrapper.dart';
import 'package:fluffychat/routes/settings/settings_subscription/selected_subscription_view.dart';

class SelectedSubscriptionPopup extends StatelessWidget {
  final ProductPlan plan;
  const SelectedSubscriptionPopup(this.plan, {super.key});

  @override
  Widget build(BuildContext context) {
    return DialogWrapper(
      backgroundColor: Theme.of(context).colorScheme.surface,
      borderRadius: 16.0,
      side: BorderSide(color: AppConfig.goldByTheme(context)),
      maxWidth: 325.0,
      maxHeight: 600.0,
      child: SelectedSubscriptionView(plan),
    );
  }
}
