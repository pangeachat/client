import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';

class SubscriptionOptionCard extends StatelessWidget {
  static const double _borderRadius = 12.0;

  final ProductPlan plan;
  final VoidCallback onTap;
  final bool selected;
  const SubscriptionOptionCard(
    this.plan, {
    super.key,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final textStyle = isColumnMode
        ? theme.textTheme.titleMedium
        : theme.textTheme.titleSmall;

    final frameColor = selected
        ? AppConfig.goldByTheme(context)
        : theme.colorScheme.primaryContainer;

    // The title sits on [frameColor], so its ink follows the frame — gold is a
    // light fill in both themes, where onPrimaryContainer is unreadable (#8303).
    final foregroundColor = selected
        ? AppConfig.onGoldByTheme(context)
        : theme.colorScheme.onPrimaryContainer;

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${plan.duration.cardTitle(l10n)}, ${plan.duration.copy(l10n)}, ${plan.priceDisplay}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(_borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_borderRadius),
          child: FrameContainer(
            title: plan.duration.cardTitle(l10n),
            frameColor: frameColor,
            backgroundColor: theme.colorScheme.surface,
            foregroundColor: foregroundColor,
            padding: EdgeInsets.all(8.0),
            titlePadding: EdgeInsetsGeometry.symmetric(
              vertical: 8.0,
              horizontal: 2.0,
            ),
            borderRadius: _borderRadius,
            titleStyle: textStyle?.copyWith(
              fontWeight: FontWeight.bold,
              color: foregroundColor,
            ),
            child: Column(
              spacing: 8.0,
              children: [
                Text(
                  plan.duration.copy(l10n),
                  style: textStyle?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(plan.priceDisplay, style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
