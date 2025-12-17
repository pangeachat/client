import 'package:fluffychat/config/app_config.dart';
import 'package:flutter/material.dart';

/// A simple choice card that doesn't flip - just shows correct/incorrect tint.
/// Used for audio and default choice cards.
class BasicChoiceCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final bool isCorrect;
  final double height;

  const BasicChoiceCard({
    required this.child,
    required this.onPressed,
    required this.isCorrect,
    this.height = 72.0,
    super.key,
  });

  @override
  State<BasicChoiceCard> createState() => BasicChoiceCardState();
}

class BasicChoiceCardState extends State<BasicChoiceCard> {
  bool _clicked = false;
  bool _isHovered = false;

  void _handleTap() {
    if (_clicked) return;

    setState(() => _clicked = true);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Color baseColor = colorScheme.surfaceContainerHighest;
    final Color hoverColor = colorScheme.onSurface.withValues(alpha: 0.08);
    final Color tintColor = widget.isCorrect
        ? AppConfig.success.withValues(alpha: 0.3)
        : AppConfig.error.withValues(alpha: 0.3);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: GestureDetector(
          onTap: _handleTap,
          child: Container(
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(16),
            ),
            foregroundDecoration: BoxDecoration(
              color: _clicked
                  ? tintColor
                  : (_isHovered ? hoverColor : Colors.transparent),
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            height: widget.height,
            alignment: Alignment.center,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
