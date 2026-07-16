import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';

class UserSubscriptionPlanCard extends StatelessWidget {
  final String subscriptionTitle;
  final String? paymentPeriodDescription;
  final String? priceDisplay;

  final bool showCancel;
  final ValueNotifier<bool>? canCancelNotifier;
  final VoidCallback? onCancel;

  final bool showManage;
  final ValueNotifier<bool>? canManageNotifier;
  final VoidCallback? onManage;

  const UserSubscriptionPlanCard({
    super.key,
    required this.subscriptionTitle,
    this.paymentPeriodDescription,
    this.priceDisplay,
    this.showCancel = false,
    this.canCancelNotifier,
    this.onCancel,
    this.showManage = false,
    this.canManageNotifier,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceDisplay = this.priceDisplay;
    final paymentPeriodDescription = this.paymentPeriodDescription;

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onSurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(width: 1, color: theme.colorScheme.onSurface),
        borderRadius: BorderRadius.circular(100),
      ),
      padding: EdgeInsets.symmetric(vertical: 0.0, horizontal: 12.0),
    );

    return FrameContainer(
      title: L10n.of(context).yourPlan,
      frameColor: theme.colorScheme.primaryContainer,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
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
              Expanded(
                child: Text(
                  subscriptionTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (priceDisplay != null)
                Text(
                  priceDisplay,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          if (paymentPeriodDescription != null)
            Text(
              paymentPeriodDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.disabledColor,
              ),
            ),
          if (showManage || showCancel)
            Row(
              spacing: 12.0,
              children: [
                if (showManage)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final content = Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Text(L10n.of(context).change)],
                        );

                        final canManageNotifier = this.canManageNotifier;
                        if (canManageNotifier != null) {
                          return ValueListenableBuilder(
                            valueListenable: canManageNotifier,
                            builder: (context, canManage, _) => ElevatedButton(
                              onPressed: canManage ? onManage : null,
                              style: buttonStyle,
                              child: content,
                            ),
                          );
                        }

                        return ElevatedButton(
                          onPressed: null,
                          style: buttonStyle,
                          child: content,
                        );
                      },
                    ),
                  ),
                if (showCancel)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final content = Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Text(L10n.of(context).cancel)],
                        );

                        final canCancelNotifier = this.canCancelNotifier;
                        if (canCancelNotifier != null) {
                          return ValueListenableBuilder(
                            valueListenable: canCancelNotifier,
                            builder: (context, canCancel, _) => ElevatedButton(
                              onPressed: canCancel ? onCancel : null,
                              style: buttonStyle,
                              child: content,
                            ),
                          );
                        }

                        return ElevatedButton(
                          onPressed: null,
                          style: buttonStyle,
                          child: content,
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
