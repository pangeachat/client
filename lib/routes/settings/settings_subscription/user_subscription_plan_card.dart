import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';

class UserSubscriptionPlanCard extends StatelessWidget {
  final String subscriptionTitle;
  final String? paymentPeriodDescription;
  final String? priceDisplay;

  final bool showCancel;
  final VoidCallback? onCancel;

  const UserSubscriptionPlanCard({
    super.key,
    required this.subscriptionTitle,
    this.paymentPeriodDescription,
    this.priceDisplay,
    this.showCancel = false,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceDisplay = this.priceDisplay;
    final paymentPeriodDescription = this.paymentPeriodDescription;

    return FrameContainer(
      title: L10n.of(context).yourPlan,
      frameColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onPrimary,
      padding: EdgeInsets.all(8.0),
      titlePadding: EdgeInsetsGeometry.symmetric(
        vertical: 8.0,
        horizontal: 12.0,
      ),
      borderRadius: 12.0,
      child: Column(
        spacing: 8.0,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(subscriptionTitle)),
              if (priceDisplay != null) Text(priceDisplay),
            ],
          ),
          if (paymentPeriodDescription != null) Text(paymentPeriodDescription),
          if (showCancel)
            ElevatedButton(
              onPressed: onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    width: 1,
                    color: theme.colorScheme.onSurface,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                padding: EdgeInsets.symmetric(vertical: 0.0, horizontal: 12.0),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Text(L10n.of(context).cancel)],
              ),
            ),
        ],
      ),
    );
  }
}
