import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription.dart';

class SubscriptionManagementButtons extends StatelessWidget {
  final SubscriptionManagementController controller;
  const SubscriptionManagementButtons({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final appID = controller.subscriptionController.currentSubscriptionInfo
        ?.currentSubscription?.appId;

    if (appID == null || !controller.showManagementOptions) {
      return const SizedBox(height: 60.0);
    }

    return Column(
      spacing: 8.0,
      children: [
        ElevatedButton(
          onPressed: () => controller.launchMangementUrl(
            ManagementOption.history,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(L10n.of(context).paymentHistory),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: () => controller.launchMangementUrl(
            ManagementOption.paymentMethod,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(L10n.of(context).paymentMethod),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: () => controller.launchMangementUrl(
            ManagementOption.cancel,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(L10n.of(context).cancelSubscription),
            ],
          ),
        ),
      ],
    );
  }
}
