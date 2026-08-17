import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/subscription/repo_v2/subscription_management_repo.dart';
import 'package:fluffychat/features/subscription/utils/storefront_gate.dart';
import 'package:fluffychat/features/subscription/widgets/decorative_stars.dart';
import 'package:fluffychat/features/subscription/widgets/locked_preview_banner.dart';
import 'package:fluffychat/features/subscription/widgets/locked_shimmer_box.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The writing-assistance gate, shown over the input bar when an unsubscribed
/// user reaches for corrections.
///
/// Styled as the word card is: a shimmer skeleton of the assistance they'd get,
/// decorative stars, and the gold unlock call to action. It used to describe the
/// whole product in a paragraph over a bot face; the gates were normalized on
/// showing the feature instead of explaining it (#7929).
class PaywallCard extends StatelessWidget {
  static const double _width = 325.0;

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

    return Container(
      width: _width,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: AppConfig.goldByTheme(context)),
        borderRadius: BorderRadius.circular(20.0),
      ),
      child: Stack(
        children: [
          // Listed first so the stars paint BEHIND the title and the call to
          // action rather than over them. Pulled in off the corners and given
          // unequal insets and sizes — pinned to opposite corners they framed
          // the card instead of scattering across it (#7929 review).
          const DecorativeStars(
            stars: [
              DecorativeStarSpec(
                size: 60.0,
                top: 4.0,
                left: 96.0,
                rotation: -0.28,
              ),
              DecorativeStarSpec(
                size: 48.0,
                bottom: 10.0,
                right: 76.0,
                rotation: 0.42,
              ),
            ],
          ),
          Column(
            spacing: 12.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 40.0,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: L10n.of(context).close,
                      color: theme.iconTheme.color,
                      icon: const Icon(Icons.close),
                      onPressed: MatrixState.pAnyState.closeOverlay,
                    ),
                    Flexible(
                      child: Container(
                        alignment: Alignment.center,
                        child: Text(
                          L10n.of(context).clickMessageTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 40.0, height: 40.0),
                  ],
                ),
              ),
              LockedPreviewBanner(
                label: L10n.of(context).unlockWritingAssistance,
                fontSize: 16.0,
                inset: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 6.0,
                ),
                buttonPadding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 10.0,
                ),
              ),
              // Stands in for the corrections themselves.
              const Row(
                spacing: 12.0,
                children: [
                  Expanded(
                    child: LockedShimmerBox(width: double.infinity, height: 56),
                  ),
                  Expanded(
                    child: LockedShimmerBox(width: double.infinity, height: 56),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
