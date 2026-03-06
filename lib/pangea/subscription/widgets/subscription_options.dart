// Flutter imports:

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';

class SubscriptionOptions extends StatelessWidget {
  final PangeaController pangeaController;
  const SubscriptionOptions({super.key, required this.pangeaController});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      direction: Axis.horizontal,
      spacing: 10,
      children: pangeaController.userController.inTrialWindow()
          ? [
              SubscriptionCard(
                onTap: () => pangeaController.subscriptionController
                    .activateNewUserTrial(),
                title: L10n.of(context).freeTrial,
                description: L10n.of(context).freeTrialDesc,
                buttonText: L10n.of(context).activateTrial,
              ),
            ]
          : pangeaController
                .subscriptionController
                .availableSubscriptionInfo!
                .availableSubscriptions
                .map(
                  (subscription) => SubscriptionCard(
                    subscription: subscription,
                    onTap: () {
                      pangeaController.subscriptionController
                          .submitSubscriptionChange(subscription, context);
                    },
                    title: subscription.displayName(context),
                    enabled: !subscription.isTrial,
                    description: subscription.isTrial
                        ? L10n.of(context).trialPeriodExpired
                        : null,
                  ),
                )
                .toList(),
    );
  }
}

class SubscriptionCard extends StatelessWidget {
  final SubscriptionDetails? subscription;
  final void Function()? onTap;
  final String? title;
  final String? description;
  final String? buttonText;
  final bool enabled;

  const SubscriptionCard({
    super.key,
    this.subscription,
    required this.onTap,
    this.title,
    this.description,
    this.buttonText,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.75,
        child: SizedBox(
          width: AppConfig.columnWidth * 0.6,
          height: 200,
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title ?? subscription?.displayName(context) ?? '',
                  textAlign: TextAlign.center,
                ),
                Text(
                  description ?? subscription?.displayPrice(context) ?? '',
                  textAlign: TextAlign.center,
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: enabled
                      ? () {
                          if (onTap != null) onTap!();
                          Navigator.of(context).pop();
                        }
                      : null,
                  // style: buttonStyle,
                  child: Row(
                    mainAxisAlignment: .center,
                    children: [Text(buttonText ?? L10n.of(context).subscribe)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
