import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/utils/bot_style.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/subscription/repo/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/widgets/subscription_paywall.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/card_header.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PaywallCard extends StatelessWidget {
  const PaywallCard({super.key});

  static Future<void> show(
    BuildContext context,
    String targetId, {
    bool force = false,
  }) async {
    if (!force &&
        !MatrixState
            .pangeaController
            .subscriptionController
            .shouldShowPaywall) {
      return;
    }

    await SubscriptionManagementRepo.setDismissedPaywall();
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: const PaywallCard(),
      displayDetails: PositionedOverlayDisplayDetails(
        overlayKey: "paywall_card_overlay",
        maxHeight: 325,
        maxWidth: 325,
        transformTargetId: targetId,
      ),
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
                  SubscriptionPaywall.show(
                    context,
                    userID: Matrix.of(context).client.userID,
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withAlpha(25),
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
