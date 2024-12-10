// Flutter imports:

import 'package:fluffychat/pangea/pages/settings_subscription/change_subscription.dart';
import 'package:fluffychat/pangea/pages/settings_subscription/settings_subscription.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:intl/intl.dart';

class SettingsSubscriptionView extends StatelessWidget {
  final SubscriptionManagementController controller;
  const SettingsSubscriptionView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final List<Widget> managementButtons = [
      if (controller.currentSubscriptionAvailable)
        ListTile(
          title: Text(L10n.of(context).currentSubscription),
          subtitle: Text(controller.currentSubscriptionTitle),
          trailing: Text(controller.currentSubscriptionPrice),
        ),
      Column(
        children: [
          ListTile(
            title: Text(L10n.of(context).cancelSubscription),
            enabled: controller.showManagementOptions,
            onTap: () => controller.launchMangementUrl(
              ManagementOption.cancel,
            ),
            trailing: const Icon(Icons.cancel_outlined),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(L10n.of(context).paymentMethod),
            trailing: const Icon(Icons.credit_card),
            onTap: () => controller.launchMangementUrl(
              ManagementOption.paymentMethod,
            ),
            enabled: controller.showManagementOptions,
          ),
          ListTile(
            title: Text(L10n.of(context).paymentHistory),
            trailing: const Icon(Icons.keyboard_arrow_right_outlined),
            onTap: () => controller.launchMangementUrl(
              ManagementOption.history,
            ),
            enabled: controller.showManagementOptions,
          ),
        ],
      ),
    ];

    final isSubscribed = controller.subscriptionController.isSubscribed;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          L10n.of(context).subscriptionManagement,
        ),
      ),
      body: ListTileTheme(
        iconColor: Theme.of(context).textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          child: Column(
            children: [
              if (isSubscribed && !controller.showManagementOptions)
                ManagementNotAvailableWarning(
                  controller: controller,
                ),
              if (!isSubscribed || controller.isNewUserTrial)
                ChangeSubscription(controller: controller),
              if (controller.showManagementOptions) ...managementButtons,
            ],
          ),
        ),
      ),
    );
  }
}

class ManagementNotAvailableWarning extends StatelessWidget {
  final SubscriptionManagementController controller;

  const ManagementNotAvailableWarning({
    required this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final currentSubscriptionInfo =
        controller.subscriptionController.currentSubscriptionInfo;

    String getWarningText() {
      final DateFormat formatter = DateFormat('yyyy-MM-dd');
      if (controller.isNewUserTrial) {
        return L10n.of(context).trialExpiration(
          formatter.format(currentSubscriptionInfo!.expirationDate!),
        );
      }
      if (controller.currentSubscriptionAvailable) {
        String warningText = L10n.of(context).subsciptionPlatformTooltip;
        if (controller.purchasePlatformDisplayName != null) {
          warningText +=
              "\n${L10n.of(context).originalSubscriptionPlatform(controller.purchasePlatformDisplayName!)}";
        }
        return warningText;
      }
      if (controller.currentSubscriptionIsPromotional) {
        if (currentSubscriptionInfo?.isLifetimeSubscription ?? false) {
          return L10n.of(context).promotionalSubscriptionDesc;
        }
        return L10n.of(context).promoSubscriptionExpirationDesc(
          formatter.format(currentSubscriptionInfo!.expirationDate!),
        );
      }
      return L10n.of(context).subscriptionManagementUnavailable;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          getWarningText(),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
