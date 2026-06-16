// Flutter imports:

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/subscription/models/subscription_details.dart';
import 'package:fluffychat/pangea/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/pangea/subscription/widgets/subscription_options.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SubscriptionPaywall extends StatelessWidget {
  final List<SubscriptionDetails> availableSubscriptions;
  const SubscriptionPaywall({super.key, required this.availableSubscriptions});

  static Future<void> show(
    BuildContext context, {
    required String? userID,
  }) async {
    try {
      final sub = MatrixState.pangeaController.subscriptionController;
      await sub.initialize(userID);

      final subscriptions = sub.availableSubscriptions;
      if (subscriptions.isEmpty) return;
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
          return SubscriptionPaywall(availableSubscriptions: subscriptions);
        },
      );
      await SubscriptionManagementRepo.setDismissedPaywall();
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: SubscriptionOptions(
                  availableSubscriptions: availableSubscriptions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
