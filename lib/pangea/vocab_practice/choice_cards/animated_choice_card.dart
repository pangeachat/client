import 'package:fluffychat/config/app_config.dart';
import 'package:flutter/material.dart';

/// A reusable animated choice card that handles tap animations and correct/incorrect styling.
class AnimatedChoiceCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final bool isCorrect;
  final double height;

  const AnimatedChoiceCard({
    required this.child,
    required this.onPressed,
    required this.isCorrect,
    this.height = 72.0,
    super.key,
  });

  @override
  State<AnimatedChoiceCard> createState() => AnimatedChoiceCardState();
}

class AnimatedChoiceCardState extends State<AnimatedChoiceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  bool _flipped = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );

    _scaleAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.addListener(_onAnimationUpdate);
  }

  void _onAnimationUpdate() {
    // Mark as flipped when card is fully shrunk
    if (_controller.value >= 0.95 && !_flipped) {
      setState(() => _flipped = true);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onAnimationUpdate);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_flipped) return;

    // Animate forward (shrink), then reverse (expand)
    await _controller.forward();
    await _controller.reverse();

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
          child: AnimatedBuilder(
            animation: _scaleAnim,
            builder: (context, child) {
              // Hide content when card is very small
              final bool showContent = _scaleAnim.value > 0.1;

              return Transform.scale(
                scaleY: _scaleAnim.value,
                child: Container(
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  foregroundDecoration: BoxDecoration(
                    color: _flipped
                        ? tintColor
                        : (_isHovered ? hoverColor : Colors.transparent),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  height: widget.height,
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: showContent ? 1.0 : 0.0,
                    child: widget.child,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
