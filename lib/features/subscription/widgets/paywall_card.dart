import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/bot/utils/bot_style.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/utils/storefront_gate.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PaywallCard extends StatelessWidget {
  const PaywallCard({super.key});

  static Future<void> show(
    BuildContext context,
    String targetId, {
    bool force = false,
  }) async {
    final subscription = MatrixState.pangeaController.subscriptionController;
    // A purchase call to action may appear only on the full-paywall tier; where
    // the storefront doesn't allow steering the upsell stays hidden (the
    // subscription settings page shows the compliant per-tier message instead).
    if (subscription.purchasePresentation != PurchasePresentation.full) {
      return;
    }
    if (!force && !subscription.shouldShowPaywall) {
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
        addBorder: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = AppConfig.goldByTheme(context);
    final onGold = theme.brightness == Brightness.light
        ? theme.colorScheme.onSurface
        : theme.colorScheme.surface;

    return Container(
      width: 325.0,
      padding: EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: gold),
        borderRadius: BorderRadius.circular(20.0),
      ),
      child: Column(
        spacing: 10.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  spacing: 8.0,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: BotFace(
                        width: 40.0,
                        expression: BotExpression.addled,
                      ),
                    ),
                    Text(
                      L10n.of(context).clickMessageTitle,
                      style: BotStyle.text(context, bold: true),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: L10n.of(context).close,
                icon: const Icon(Icons.close_outlined),
                onPressed: MatrixState.pAnyState.closeOverlay,
              ),
            ],
          ),
          Column(
            spacing: 12.0,
            children: [
              Text(
                L10n.of(context).subscribedToUnlockTools,
                style: theme.textTheme.bodyMedium,
              ),
              ElevatedButton(
                onPressed: () => context.go(
                  WorkspaceNav.openSettings(
                    GoRouterState.of(context).uri,
                    page: 'subscription',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: onGold,
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Text(L10n.of(context).viewSubscriptionOptions)],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
