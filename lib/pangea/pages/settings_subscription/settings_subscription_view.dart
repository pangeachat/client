// Flutter imports:

import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:intl/intl.dart';

import 'package:fluffychat/pangea/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/pages/settings_subscription/change_subscription.dart';
import 'package:fluffychat/pangea/pages/settings_subscription/settings_subscription.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SettingsSubscriptionView extends StatelessWidget {
  final SubscriptionManagementController controller;
  final PangeaController pangeaController = MatrixState.pangeaController;
  SettingsSubscriptionView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final String currentSubscriptionTitle = pangeaController
            .subscriptionController.subscription?.currentSubscription
            ?.displayName(context) ??
        "";
    final String currentSubscriptionPrice = pangeaController
            .subscriptionController.subscription?.currentSubscription
            ?.displayPrice(context) ??
        "";

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          L10n.of(context)!.subscriptionManagement,
        ),
      ),
      body: ListTileTheme(
        iconColor: Theme.of(context).textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          child: !(pangeaController.subscriptionController.isSubscribed)
              ? ChangeSubscription(controller: controller)
              : Column(
                  children: [
                    if (pangeaController.subscriptionController.subscription!
                            .currentSubscription !=
                        null)
                      ListTile(
                        title: Text(L10n.of(context)!.currentSubscription),
                        subtitle: Text(currentSubscriptionTitle),
                        trailing: Text(currentSubscriptionPrice),
                      ),
                    Column(
                      children: [
                        ListTile(
                          title: Text(L10n.of(context)!.cancelSubscription),
                          enabled: controller.showManagementOptions,
                          onTap: () => controller.launchMangementUrl(
                            ManagementOption.cancel,
                          ),
                          trailing: const Icon(Icons.cancel_outlined),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: Text(L10n.of(context)!.paymentMethod),
                          trailing: const Icon(Icons.credit_card),
                          onTap: () => controller.launchMangementUrl(
                            ManagementOption.paymentMethod,
                          ),
                          enabled: controller.showManagementOptions,
                        ),
                        ListTile(
                          title: Text(L10n.of(context)!.paymentHistory),
                          trailing:
                              const Icon(Icons.keyboard_arrow_right_outlined),
                          onTap: () => controller.launchMangementUrl(
                            ManagementOption.history,
                          ),
                          enabled: controller.showManagementOptions,
                        ),
                      ],
                    ),
                    const SizedBox(height: 50),
                    if (!(controller.showManagementOptions))
                      ManagementNotAvailableWarning(
                        controller: controller,
                        subscriptionController:
                            pangeaController.subscriptionController,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class ManagementNotAvailableWarning extends StatelessWidget {
  final SubscriptionManagementController controller;
  final SubscriptionController subscriptionController;

  const ManagementNotAvailableWarning({
    required this.controller,
    required this.subscriptionController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    String getWarningText() {
      final DateFormat formatter = DateFormat('yyyy-MM-dd');
      if (controller.isNewUserTrial) {
        return L10n.of(context)!.trialExpiration(
          formatter.format(
            subscriptionController.subscription!.expirationDate!,
          ),
        );
      }
      if (controller.currentSubscriptionAvailable) {
        String warningText = L10n.of(context)!.subsciptionPlatformTooltip;
        if (controller.purchasePlatformDisplayName != null) {
          warningText +=
              "\n${L10n.of(context)!.originalSubscriptionPlatform(controller.purchasePlatformDisplayName!)}";
        }
        return warningText;
      }
      if (controller.currentSubscriptionIsPromotional) {
        if (subscriptionController.subscription?.isLifetimeSubscription ??
            false) {
          return L10n.of(context)!.promotionalSubscriptionDesc;
        }
        return L10n.of(context)!.promoSubscriptionExpirationDesc(
          formatter.format(
            subscriptionController.subscription!.expirationDate!,
          ),
        );
      }
      return L10n.of(context)!.subscriptionManagementUnavailable;
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
