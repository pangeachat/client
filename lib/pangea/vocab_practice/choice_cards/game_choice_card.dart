import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A unified choice card that handles flipping, color tinting, hovering, and alt widgets
class GameChoiceCard extends StatefulWidget {
  final Widget child;
  final Widget? altChild;
  final VoidCallback onPressed;
  final bool isCorrect;
  final double height;
  final bool shouldFlip;
  final String targetId;
  final bool isEnabled;

  const GameChoiceCard({
    required this.child,
    this.altChild,
    required this.onPressed,
    required this.isCorrect,
    this.height = 72.0,
    this.shouldFlip = false,
    required this.targetId,
    this.isEnabled = true,
    super.key,
  });

  @override
  State<GameChoiceCard> createState() => _GameChoiceCardState();
}

class _GameChoiceCardState extends State<GameChoiceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  bool _flipped = false;
  bool _isHovered = false;
  bool _useAltChild = false;
  bool _clicked = false;

  @override
  void initState() {
    super.initState();

    if (widget.shouldFlip) {
      _controller = AnimationController(
        duration: const Duration(milliseconds: 220),
        vsync: this,
      );

      _scaleAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );

      _controller.addListener(_onAnimationUpdate);
    }
  }

  void _onAnimationUpdate() {
    // Swap to altChild when card is almost fully shrunk
    if (_controller.value >= 0.95 && !_useAltChild && widget.altChild != null) {
      setState(() => _useAltChild = true);
    }

    // Mark as flipped when card is fully shrunk
    if (_controller.value >= 0.95 && !_flipped) {
      setState(() => _flipped = true);
    }
  }

  @override
  void dispose() {
    if (widget.shouldFlip) {
      _controller.removeListener(_onAnimationUpdate);
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (!widget.isEnabled) return;

    if (widget.shouldFlip) {
      if (_flipped) return;
      // Animate forward (shrink), then reverse (expand)
      await _controller.forward();
      await _controller.reverse();
    } else {
      if (_clicked) return;
      setState(() => _clicked = true);
    }

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

    return CompositedTransformTarget(
      link: MatrixState.pAnyState.layerLinkAndKey(widget.targetId).link,
      child: MouseRegion(
        onEnter: widget.isEnabled
            ? ((_) => setState(() => _isHovered = true))
            : null,
        onExit: widget.isEnabled
            ? ((_) => setState(() => _isHovered = false))
            : null,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: GestureDetector(
            onTap: _handleTap,
            child: widget.shouldFlip
                ? AnimatedBuilder(
                    animation: _scaleAnim,
                    builder: (context, child) {
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
                                : (_isHovered
                                    ? hoverColor
                                    : Colors.transparent),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          margin: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 0,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          height: widget.height,
                          alignment: Alignment.center,
                          child: Opacity(
                            opacity: showContent ? 1.0 : 0.0,
                            child: _useAltChild && widget.altChild != null
                                ? widget.altChild!
                                : widget.child,
                          ),
                        ),
                      );
                    },
                  )
                : Container(
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
                    margin:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    height: widget.height,
                    alignment: Alignment.center,
                    child: widget.child,
                  ),
          ),
        ),
      ),
    );
  }
}
