import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';

/// The course page's secondary action (#9420): a light-purple
/// (secondary container) pill on a pressable lip with a bold label, so it
/// reads as a button beside the Mission card's solid Play rather than as a
/// flat tonal chip. With no [label] it draws a circle around [icon] alone.
class BoldTonalButton extends StatelessWidget {
  final IconData? icon;
  final String? label;

  /// The accessible name, when it should say more than [label] (or there is
  /// no label).
  final String? semanticsLabel;

  /// Drawn after the label, e.g. a count chip.
  final Widget? trailing;

  final VoidCallback? onPressed;
  final double height;
  final double iconSize;

  /// Fill the width it is given (a full-width row action); otherwise it hugs
  /// its content, even inside a row that hands it a bounded width.
  final bool expand;

  const BoldTonalButton({
    required this.onPressed,
    this.icon,
    this.label,
    this.semanticsLabel,
    this.trailing,
    this.height = 38.0,
    this.iconSize = 18.0,
    this.expand = false,
    super.key,
  }) : assert(icon != null || label != null);

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(999.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = scheme.secondaryContainer;
    final ink = scheme.onSecondaryContainer;
    final label = this.label;
    final iconOnly = label == null;
    final button = Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel ?? label,
      // The pressable below is excluded, so the tap is published here.
      onTap: onPressed,
      child: ExcludeSemantics(
        child: PressableButton(
          borderRadius: _radius,
          color: fill,
          onPressed: onPressed,
          builder: (context, depressed, shadowColor) => Container(
            height: height,
            width: iconOnly ? height : null,
            padding: iconOnly
                ? null
                : const EdgeInsets.symmetric(horizontal: 14.0),
            decoration: BoxDecoration(
              color: depressed ? shadowColor : fill,
              borderRadius: _radius,
            ),
            child: Center(
              widthFactor: expand ? null : 1.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6.0,
                children: [
                  if (icon != null) Icon(icon, size: iconSize, color: ink),
                  if (label != null)
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = semanticsLabel ?? label;
    return tooltip == null
        ? button
        : Tooltip(message: tooltip, excludeFromSemantics: true, child: button);
  }
}
