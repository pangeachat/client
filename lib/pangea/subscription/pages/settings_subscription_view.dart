import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/pages/change_subscription.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription.dart';
import 'package:fluffychat/pangea/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/pangea/subscription/subscription_constants.dart';
import 'package:fluffychat/pangea/subscription/widgets/pro_features_card.dart';

class SettingsSubscriptionView extends StatelessWidget {
  final SubscriptionManagementController controller;
  const SettingsSubscriptionView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final clickedCancelDate =
        SubscriptionManagementRepo.getClickedCancelSubscription();

    final showWaitingForChangeWarning =
        clickedCancelDate != null &&
        DateTime.now().difference(clickedCancelDate).inMinutes < 10;

    final hasFreeTrial = controller.hasFreeTrial;
    final showGatedContent = controller.showGatedContent;

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(L10n.of(context).subscriptionManagement),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl:
                "${AppConfig.assetsBaseURL}/${SubscriptionConstants.starBackground}",
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                const ColoredBox(color: Colors.black12),
            errorWidget: (context, url, error) => const SizedBox(),
          ),
          SingleChildScrollView(
            child: ListTileTheme(
              iconColor: theme.textTheme.bodyLarge!.color,
              child: Container(
                alignment: Alignment.topCenter,
                padding: EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 600),
                  child: Column(
                    spacing: 16.0,
                    children: [
                      ProFeaturesCard(),
                      Material(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppConfig.borderRadius,
                          ),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Column(
                            children: [
                              if (controller.loading)
                                const Center(
                                  child: CircularProgressIndicator.adaptive(),
                                )
                              else if (showGatedContent &&
                                  !controller.showManagementOptions)
                                ManagementNotAvailableWarning(
                                  controller: controller,
                                )
                              else if (showGatedContent &&
                                  controller.showManagementOptions) ...[
                                if (controller.currentSubscriptionAvailable)
                                  ListTile(
                                    title: Text(
                                      L10n.of(context).currentSubscription,
                                    ),
                                    subtitle: Text(
                                      controller.currentSubscriptionTitle,
                                    ),
                                    trailing: Text(
                                      controller.currentSubscriptionPrice,
                                    ),
                                  ),
                                Column(
                                  children: [
                                    ListTile(
                                      title: Text(
                                        controller.subscriptionEndDate == null
                                            ? L10n.of(
                                                context,
                                              ).cancelSubscription
                                            : L10n.of(context).enabledRenewal,
                                      ),
                                      enabled: controller.showManagementOptions,
                                      onTap:
                                          controller.onClickCancelSubscription,
                                      trailing: Icon(
                                        controller.subscriptionEndDate == null
                                            ? Icons.cancel_outlined
                                            : Icons.refresh_outlined,
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    ListTile(
                                      title: Text(
                                        L10n.of(context).paymentMethod,
                                      ),
                                      trailing: const Icon(Icons.credit_card),
                                      onTap: () =>
                                          controller.launchMangementUrl(
                                            ManagementOption.paymentMethod,
                                          ),
                                      enabled: controller.showManagementOptions,
                                    ),
                                    ListTile(
                                      title: Text(
                                        L10n.of(context).paymentHistory,
                                      ),
                                      trailing: const Icon(
                                        Icons.keyboard_arrow_right_outlined,
                                      ),
                                      onTap: () =>
                                          controller.launchMangementUrl(
                                            ManagementOption.history,
                                          ),
                                      enabled: controller.showManagementOptions,
                                    ),
                                    if (controller.expirationDate != null) ...[
                                      const Divider(height: 1),
                                      ListTile(
                                        title: Text(
                                          controller.subscriptionEndDate != null
                                              ? L10n.of(
                                                  context,
                                                ).subscriptionEndsOn
                                              : L10n.of(
                                                  context,
                                                ).subscriptionRenewsOn,
                                        ),
                                        subtitle: Text(
                                          DateFormat.yMMMMd().format(
                                            controller.expirationDate!
                                                .toLocal(),
                                          ),
                                        ),
                                      ),
                                      if (showWaitingForChangeWarning)
                                        Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Row(
                                            spacing: 8.0,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.info_outline,
                                                size: 20,
                                              ),
                                              Flexible(
                                                child: Text(
                                                  L10n.of(
                                                    context,
                                                  ).waitForSubscriptionChanges,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ],
                              if (hasFreeTrial) ...[
                                Divider(),
                                SizedBox(height: 16.0),
                              ],
                              if (!showGatedContent || hasFreeTrial)
                                ChangeSubscription(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ManagementNotAvailableWarning extends StatelessWidget {
  final SubscriptionManagementController controller;

  const ManagementNotAvailableWarning({required this.controller, super.key});

  String getWarningText(BuildContext context) {
    if (controller.currentSubscriptionIsPromotional) {
      if (controller.isLifetimeSubscription) {
        return L10n.of(context).promotionalSubscriptionDesc;
      }

      final DateFormat formatter = DateFormat('yyyy-MM-dd');
      return L10n.of(
        context,
      ).trialExpiration(formatter.format(controller.expirationDate!));
    }
    if (controller.currentSubscriptionAvailable) {
      String warningText = L10n.of(context).subsciptionPlatformTooltip;
      if (controller.purchasePlatformDisplayName != null) {
        warningText +=
            "\n${L10n.of(context).originalSubscriptionPlatform(controller.purchasePlatformDisplayName!)}";
      }
      return warningText;
    }
    return L10n.of(context).subscriptionManagementUnavailable;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(getWarningText(context), textAlign: TextAlign.center),
      ),
    );
  }
}
