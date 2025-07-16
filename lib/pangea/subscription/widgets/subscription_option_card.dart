import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/subscription/pages/settings_subscription.dart';

class SubscriptionOptionCard extends StatelessWidget {
  final SubscriptionDetails subscription;
  final SubscriptionManagementController controller;

  const SubscriptionOptionCard({
    super.key,
    required this.subscription,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final selected = controller.selectedSubscription?.id == subscription.id;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => controller.selectSubscription(subscription),
        child: Opacity(
          opacity: selected ? 1.0 : 0.5,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.disabledColor,
                width: 2.0,
              ),
              borderRadius: BorderRadius.circular(10.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.primaryContainer
                        : theme.disabledColor,
                  ),
                  padding: const EdgeInsets.all(4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        subscription.displayPrice(context),
                        style: TextStyle(
                          fontSize: isColumnMode ? 24 : 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsGeometry.symmetric(
                    horizontal: 4.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    spacing: 12.0,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt,
                            size: isColumnMode ? 24 : 16,
                            color: AppConfig.yellowDark,
                          ),
                          Text(
                            subscription.isFree
                                ? L10n.of(context).fiftyPerDay
                                : L10n.of(context).unlimited,
                            style: TextStyle(
                              fontSize: isColumnMode ? 20 : 12,
                              color: AppConfig.yellowDark,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        subscription.duration?.description(context) ??
                            L10n.of(context).free,
                        style: TextStyle(
                          fontSize: isColumnMode ? 20 : 12,
                        ),
                      ),
                    ],
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
