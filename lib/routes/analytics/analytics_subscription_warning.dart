import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/subscription/models/subscription_state.dart';
import 'package:fluffychat/features/subscription/utils/storefront_gate.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// Tells a learner on their analytics pages that their messages are not
/// earning XP.
///
/// Writing assistance is what turns a sent message into construct uses, and it
/// is a paid feature, so a learner without a subscription keeps chatting while
/// their analytics stand still, with nothing saying why (#9119).
///
/// Shown only once the status is known to be inactive. While it is loading, or
/// after the lookup failed (the controller reports that failure), the learner
/// may well be subscribed, and the warning would flash or be wrong.
class AnalyticsSubscriptionWarning extends StatelessWidget {
  final SubscriptionController subscription;

  const AnalyticsSubscriptionWarning({required this.subscription, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: subscription.state,
      builder: (context, state, _) => state is SubscriptionInactive
          ? _AnalyticsSubscriptionWarningCard(
              // A call to purchase appears only where the storefront allows
              // steering to web checkout (subscriptions Platform policy).
              showSubscribeButton:
                  subscription.purchasePresentation ==
                  PurchasePresentation.full,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _AnalyticsSubscriptionWarningCard extends StatelessWidget {
  final bool showSubscribeButton;

  const _AnalyticsSubscriptionWarningCard({required this.showSubscribeButton});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final ink = theme.pangea.onWarningContainer;

    // The gap below lives here rather than in the page, so a hidden warning
    // leaves no empty space behind.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Semantics(
        container: true,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: theme.pangea.warningContainer,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12.0,
            children: [
              Icon(Icons.warning_amber_rounded, color: ink),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4.0,
                  children: [
                    Text(
                      l10n.analyticsSubscriptionWarningTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      l10n.analyticsSubscriptionWarningBody,
                      style: theme.textTheme.bodyMedium?.copyWith(color: ink),
                    ),
                    if (showSubscribeButton)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.pangea.warning,
                              foregroundColor: theme.colorScheme.surface,
                            ),
                            onPressed: () => context.go(
                              WorkspaceNav.openSettings(
                                GoRouterState.of(context).uri,
                                page: 'subscription',
                              ),
                            ),
                            child: Text(l10n.subscribe),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
