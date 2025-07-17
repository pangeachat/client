import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/constants/subscription_constants.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription.dart';
import 'package:fluffychat/pangea/subscription/widgets/current_subscription_info.dart';
import 'package:fluffychat/pangea/subscription/widgets/subscription_management_buttons.dart';
import 'package:fluffychat/pangea/subscription/widgets/subscription_mode_details.dart';
import 'package:fluffychat/pangea/subscription/widgets/subscription_option_card.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';

enum SubscriptionMode {
  free,
  paid;

  List<dynamic> get options {
    switch (this) {
      case SubscriptionMode.free:
        return FreeModeOptions.values;
      case SubscriptionMode.paid:
        return PaidModeOptions.values;
    }
  }

  Color borderColor(BuildContext context) {
    final theme = Theme.of(context);
    return this == SubscriptionMode.free
        ? theme.colorScheme.secondary
        : AppConfig.yellowDark;
  }

  String label(L10n l10n) {
    switch (this) {
      case SubscriptionMode.free:
        return l10n.freeModeLabel;
      case SubscriptionMode.paid:
        return l10n.paidModeLabel;
    }
  }
}

class SettingsSubscriptionView extends StatelessWidget {
  final SubscriptionManagementController controller;
  const SettingsSubscriptionView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    final String startDate = DateFormat.yMMMd().format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          L10n.of(context).subscriptionManagement,
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              child: CachedNetworkImage(
                fit: BoxFit.cover,
                imageUrl:
                    "${AppConfig.assetsBaseURL}/${SubscriptionConstants.backgroundAsset}",
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              height: double.infinity,
              width: double.infinity,
              color: Colors.black.withAlpha(200),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: MaxWidthBody(
              showBorder: false,
              maxWidth: 834,
              child: Column(
                spacing: isColumnMode ? 24.0 : 20.0,
                children: [
                  Text(
                    AppConfig.applicationName,
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.bold,
                      fontSize: isColumnMode ? 42 : 24.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (controller.subscriptionController.isSubscribed != null &&
                      controller.subscriptionController.isSubscribed! &&
                      !controller.showManagementOptions)
                    ManagementNotAvailableWarning(
                      controller: controller,
                    ),
                  (controller.subscriptionController.isSubscribed ?? false)
                      ? CurrentSubscriptionInfoWidget(
                          controller: controller,
                        )
                      : SubscriptionModeDetails(
                          mode: SubscriptionMode.free,
                          title: Text(
                            L10n.of(context).tagline,
                            style: TextStyle(fontSize: isColumnMode ? 24 : 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                  SubscriptionModeDetails(
                    mode: SubscriptionMode.paid,
                    title: Row(
                      spacing: 12.0,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt,
                          size: isColumnMode ? 40 : 24,
                          color: AppConfig.yellowDark,
                        ),
                        Text(
                          L10n.of(context).aiPowerups,
                          style: TextStyle(
                            fontSize: isColumnMode ? 32 : 16,
                            fontWeight: FontWeight.w600,
                            color: AppConfig.yellowDark,
                          ),
                        ),
                        Icon(
                          Icons.bolt,
                          size: isColumnMode ? 40 : 24,
                          color: AppConfig.yellowDark,
                        ),
                      ],
                    ),
                  ),
                  if (controller.subscriptionController.isSubscribed ?? false)
                    SubscriptionManagementButtons(controller: controller)
                  else
                    Column(
                      spacing: isColumnMode ? 24.0 : 12.0,
                      children: [
                        Text(
                          L10n.of(context).chooseYourPlan,
                          style:
                              TextStyle(fontSize: isColumnMode ? 32.0 : 16.0),
                        ),
                        Row(
                          spacing: isColumnMode ? 24.0 : 8.0,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: controller.availableSubscriptions
                              .map((subscription) {
                            return Expanded(
                              child: SubscriptionOptionCard(
                                subscription: subscription,
                                controller: controller,
                              ),
                            );
                          }).toList(),
                        ),
                        if (controller.selectedSubscription != null) ...[
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.secondary,
                              foregroundColor: theme.colorScheme.onSecondary,
                            ),
                            onPressed: controller.selectedSubscription!.isFree
                                ? null
                                : controller.submitChange,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  L10n.of(context).continueText,
                                  style: TextStyle(
                                    fontSize: isColumnMode ? 16 : 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L10n.of(context).startDate(startDate),
                                  style: TextStyle(
                                    fontSize: isColumnMode ? 16 : 12,
                                  ),
                                ),
                                Text(
                                  L10n.of(context).cancelInSubscriptionSettings,
                                  style: TextStyle(
                                    fontSize: isColumnMode ? 16 : 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
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

  const ManagementNotAvailableWarning({
    required this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final currentSubscriptionInfo =
        controller.subscriptionController.currentSubscriptionInfo;

    String getWarningText() {
      if (controller.currentSubscriptionIsPromotional) {
        if (currentSubscriptionInfo?.isLifetimeSubscription ?? false) {
          return L10n.of(context).promotionalSubscriptionDesc;
        }

        final DateFormat formatter = DateFormat('yyyy-MM-dd');
        return L10n.of(context).promoSubscriptionExpirationDesc(
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
      return L10n.of(context).subscriptionManagementUnavailable;
    }

    final isColumnMode = FluffyThemes.isColumnMode(context);
    return Center(
      child: Text(
        getWarningText(),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: isColumnMode ? 16 : 12),
      ),
    );
  }
}
