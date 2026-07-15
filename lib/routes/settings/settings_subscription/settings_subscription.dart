import 'package:flutter/material.dart';

import 'package:fluffychat/routes/settings/settings_subscription/products_provider.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription_view.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_status_provider.dart';

class SettingsSubscription extends StatelessWidget {
  final Widget closeButton;
  const SettingsSubscription({super.key, required this.closeButton});

  @override
  Widget build(BuildContext context) {
    return SubscriptionStatusProvider(
      builder: (context, subscriptionStatusState) => ProductsProvider(
        builder: (context, productsState) => SettingsSubscriptionView(
          closeButton: closeButton,
          subscriptionStatusState: subscriptionStatusState,
          productsState: productsState,
        ),
      ),
    );
  }
}
