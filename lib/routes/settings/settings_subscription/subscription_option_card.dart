import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/subscription/repo_v2/products_response.dart';
import 'package:fluffychat/features/subscription/widgets/frame_container.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// A tappable plan chip on the subscription page.
///
/// The card shares [FrameContainer] with the (non-interactive) pro-features
/// box, so the framed look alone doesn't read as clickable. The resting drop
/// shadow, the lift on hover, and the press-down on tap are what set it apart
/// as the page's main action.
class SubscriptionOptionCard extends StatefulWidget {
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
  State<SubscriptionOptionCard> createState() => _SubscriptionOptionCardState();
}

class _SubscriptionOptionCardState extends State<SubscriptionOptionCard> {
  static const _borderRadius = 12.0;
  static const _duration = Duration(milliseconds: 120);

  bool _hovered = false;
  bool _pressed = false;

  /// Hovering raises the card; pressing puts it back down under the finger.
  bool get _lifted => _hovered && !_pressed;

  /// Resting elevation, deepened while lifted and flattened while pressed.
  ///
  /// A black drop shadow reads as elevation on the light theme, but vanishes
  /// against the dark theme's near-black surface — there the same lift is cast
  /// as a soft glow in the frame's own color instead.
  BoxShadow _shadow(ThemeData theme) {
    final light = theme.brightness == Brightness.light;
    final color = light ? theme.colorScheme.shadow : theme.colorScheme.primary;
    final restAlpha = light ? 0.25 : 0.45;

    return BoxShadow(
      color: color.withValues(alpha: _pressed ? restAlpha * 0.6 : restAlpha),
      blurRadius: _pressed
          ? 2.0
          : _lifted
          ? 10.0
          : 4.0,
      offset: Offset(
        0,
        _pressed
            ? 1.0
            : _lifted
            ? 4.0
            : 2.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final textStyle = isColumnMode
        ? theme.textTheme.titleMedium
        : theme.textTheme.titleSmall;

    return Semantics(
      button: true,
      selected: widget.selected,
      label:
          '${widget.plan.duration.cardTitle(l10n)}, ${widget.plan.duration.copy(l10n)}, ${widget.plan.priceDisplay}',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: _duration,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _lifted ? -2.0 : 0.0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_borderRadius),
          boxShadow: [_shadow(theme)],
        ),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) => setState(() => _hovered = hovered),
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          borderRadius: BorderRadius.circular(_borderRadius),
          child: FrameContainer(
            title: widget.plan.duration.cardTitle(l10n),
            frameColor: widget.selected
                ? AppConfig.goldByTheme(context)
                : theme.colorScheme.primaryContainer,
            backgroundColor: theme.colorScheme.surface,
            foregroundColor: widget.selected
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
                  widget.plan.duration.copy(l10n),
                  style: textStyle?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(widget.plan.priceDisplay, style: textStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
