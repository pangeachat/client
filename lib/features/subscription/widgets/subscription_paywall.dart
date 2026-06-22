import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/models/subscription_details.dart';
import 'package:fluffychat/features/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionPaywall extends StatelessWidget {
  const SubscriptionPaywall({super.key});

  static Future<void> show(
    BuildContext context, {
    required String? userID,
  }) async {
    try {
      final sub = MatrixState.pangeaController.subscriptionController;
      await sub.initialize(userID);

      if (sub.availableSubscriptions.isEmpty) return;
      if (sub.showSubscriptionGatedContent) return;

      MatrixState.pAnyState.closeAllOverlays();
      await showModalBottomSheet(
        isScrollControlled: true,
        useRootNavigator: !PlatformInfos.isMobile,
        clipBehavior: Clip.hardEdge,
        context: context,
        constraints: BoxConstraints(
          maxHeight: PlatformInfos.isMobile
              ? MediaQuery.heightOf(context) - 50
              : 600,
        ),
        builder: (_) {
          return SubscriptionPaywall();
        },
      );
      await SubscriptionManagementRepo.setDismissedPaywall();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = MatrixState.pangeaController.subscriptionController;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: const CloseButton(),
        title: Text(
          L10n.of(context).getAccess,
          style: const TextStyle(fontSize: 20),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (Matrix.of(context).client.rooms.length > 1) ...[
                Text(
                  L10n.of(context).welcomeBack,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
              ],
              Text(
                L10n.of(context).subscriptionDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 40),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  direction: Axis.horizontal,
                  spacing: 10,
                  children:
                      MatrixState.pangeaController.userController
                          .inTrialWindow()
                      ? [
                          SubscriptionCard(
                            onTap: sub.activateNewUserTrial,
                            title: L10n.of(context).freeTrial,
                            description: L10n.of(context).freeTrialDesc,
                            buttonText: L10n.of(context).activateTrial,
                          ),
                        ]
                      : sub.availableSubscriptions
                            .map(
                              (subscription) => SubscriptionCard(
                                subscription: subscription,
                                onTap: () => showFutureLoadingDialog(
                                  context: context,
                                  future: () => sub.submitSubscriptionChange(
                                    subscription,
                                    context,
                                  ),
                                ),
                                title: subscription.displayName(context),
                                enabled: !subscription.isTrial,
                                description: subscription.isTrial
                                    ? L10n.of(context).trialPeriodExpired
                                    : null,
                              ),
                            )
                            .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
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
