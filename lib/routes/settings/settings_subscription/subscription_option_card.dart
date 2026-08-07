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

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${plan.duration.cardTitle(l10n)}, ${plan.duration.copy(l10n)}, ${plan.priceDisplay}',
      excludeSemantics: true,
      onTap: onTap,
      // The card shares [FrameContainer] with the (non-interactive)
      // pro-features box, so the framed look alone doesn't read as clickable.
      // An ElevatedButton supplies the affordance the box doesn't have — a
      // resting elevation that rises on hover and settles on press — with
      // Material's own state animation rather than a hand-rolled one.
      child: ElevatedButton(
        onPressed: onTap,
        style:
            ElevatedButton.styleFrom(
              backgroundColor: frameColor,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_borderRadius),
              ),
            ).copyWith(
              // FrameContainer paints over the button's surface, so the hover
              // and press *overlays* never show — the shadow is the only state
              // cue that reaches the eye. M3's default 1 → 3 bump is too small
              // to read on its own, so widen the ramp.
              elevation: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) return 1.0;
                if (states.contains(WidgetState.hovered)) return 8.0;
                if (states.contains(WidgetState.focused)) return 6.0;
                return 2.0;
              }),
            ),
        child: FrameContainer(
          title: plan.duration.cardTitle(l10n),
          frameColor: frameColor,
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: selected
              ? (theme.brightness == Brightness.light
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.surface)
              : theme.colorScheme.onPrimaryContainer,
          padding: EdgeInsets.all(8.0),
          titlePadding: EdgeInsetsGeometry.symmetric(
            vertical: 8.0,
            horizontal: 2.0,
          ),
          borderRadius: _borderRadius,
          titleStyle: textStyle?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
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
    );
  }
}
