import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/common/widgets/card_header.dart';
import 'package:fluffychat/pangea/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PaywallCard extends StatelessWidget {
  const PaywallCard({super.key});

  static Future<void> show(
    BuildContext context,
    String targetId,
  ) async {
    if (!MatrixState
        .pangeaController.subscriptionController.shouldShowPaywall) {
      return;
    }

    await SubscriptionManagementRepo.setDismissedPaywall();
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: const PaywallCard(),
      maxHeight: 325,
      maxWidth: 325,
      transformTargetId: targetId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 12.0,
      children: [
        CardHeader(L10n.of(context).clickMessageTitle),
        Column(
          spacing: 12.0,
          children: [
            Text(
              L10n.of(context).subscribedToUnlockTools,
              style: BotStyle.text(context),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  MatrixState.pangeaController.subscriptionController
                      .showPaywall(context);
                },
                style: TextButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withAlpha(25),
                ),
                child: Text(L10n.of(context).getAccess),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
