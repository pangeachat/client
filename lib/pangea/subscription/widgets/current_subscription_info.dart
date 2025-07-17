import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription.dart';

class CurrentSubscriptionInfoWidget extends StatelessWidget {
  final SubscriptionManagementController controller;
  const CurrentSubscriptionInfoWidget({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = MediaQuery.of(context).size.width > 600;

    final currentSubscription = controller
        .subscriptionController.currentSubscriptionInfo?.currentSubscription;

    final currentInfo =
        controller.subscriptionController.currentSubscriptionInfo;
    final startDate = currentInfo?.registrationDate;
    final renewalDate = currentInfo?.renewalDate;
    final expirationDate = currentInfo?.expirationDate;

    final formatter = DateFormat('yyyy-MM-dd');

    return Container(
      margin: EdgeInsets.only(top: isColumnMode ? 14.0 : 8.0),
      padding: EdgeInsets.symmetric(
        horizontal: isColumnMode ? 48.0 : 32.0,
        vertical: isColumnMode ? 16.0 : 8.0,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: AppConfig.yellowDark,
          width: isColumnMode ? 4.0 : 1.0,
        ),
        borderRadius: BorderRadius.circular(24.0),
        color:
            theme.brightness == Brightness.light ? Colors.white : Colors.black,
      ),
      child: Column(
        spacing: 12.0,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 12.0,
            children: [
              Icon(
                Icons.bolt,
                size: isColumnMode ? 40 : 24,
                color: AppConfig.yellowDark,
              ),
              Text(
                L10n.of(context).proPlan,
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
          if (startDate != null)
            Text(
              L10n.of(context).registrationDate(
                formatter.format(startDate),
              ),
              style: TextStyle(
                fontSize: isColumnMode ? 40 : 20,
              ),
            ),
          if (currentSubscription?.duration != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currentSubscription!.duration!.fullName(context),
                  style: TextStyle(fontSize: isColumnMode ? 20 : 12),
                ),
                Text(
                  currentSubscription.displayPrice(context),
                  style: TextStyle(fontSize: isColumnMode ? 20 : 12),
                ),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                L10n.of(context).powerups,
                style: TextStyle(fontSize: isColumnMode ? 20 : 12),
              ),
              Text(
                L10n.of(context).unlimited,
                style: TextStyle(fontSize: isColumnMode ? 20 : 12),
              ),
            ],
          ),
          if (!currentInfo!.isLifetimeSubscription && renewalDate != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  L10n.of(context).renewOn,
                  style: TextStyle(fontSize: isColumnMode ? 20 : 12),
                ),
                Text(
                  formatter.format(renewalDate),
                  style: TextStyle(fontSize: isColumnMode ? 20 : 12),
                ),
              ],
            )
          else if (!currentInfo.isLifetimeSubscription &&
              expirationDate != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  L10n.of(context).expiresOn,
                  style: TextStyle(fontSize: isColumnMode ? 20 : 12),
                ),
                Text(
                  formatter.format(expirationDate),
                  style: TextStyle(fontSize: isColumnMode ? 20 : 12),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
