import 'package:flutter/material.dart';

class WordZoomActivityButton extends StatelessWidget {
  final Widget icon;
  final bool isSelected;
  final VoidCallback onPressed;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final double? opacity;
  final bool isEnabled;

  const WordZoomActivityButton({
    required this.icon,
    required this.isSelected,
    required this.onPressed,
    this.onDoubleTap,
    this.onLongPress,
    this.tooltip,
    this.opacity,
    super.key,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget buttonContent = IconButton(
      icon: Transform.scale(
        scale: isSelected ? 1.25 : 1.0,
        child: icon,
      ),
      onPressed: null, // Disable IconButton's onPressed
      iconSize: 24,
      color: isSelected ? Theme.of(context).colorScheme.primary : null,
      visualDensity: VisualDensity.compact,
    );

    if (opacity != null) {
      buttonContent = Opacity(
        opacity: opacity!,
        child: buttonContent,
      );
    }

    if (tooltip != null) {
      buttonContent = Tooltip(
        message: tooltip!,
        child: buttonContent,
      );
    }

    return GestureDetector(
      onTap: onPressed,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: buttonContent,
    );
  }
}
