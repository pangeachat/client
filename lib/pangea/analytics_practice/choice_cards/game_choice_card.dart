import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
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
  final bool shrinkWrap;

  const GameChoiceCard({
    required this.child,
    required this.onPressed,
    required this.isCorrect,
    required this.targetId,
    this.altChild,
    this.height = 72.0,
    this.shouldFlip = false,
    this.isEnabled = true,
    this.shrinkWrap = false,
    super.key,
  });

  @override
  State<GameChoiceCard> createState() => _GameChoiceCardState();
}

class _GameChoiceCardState extends State<GameChoiceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  bool _clicked = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );

    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 1.0, end: 0.0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (!widget.isEnabled) return;
    widget.onPressed();

    if (widget.shouldFlip) {
      if (_controller.isAnimating || _revealed) return;

      await _controller.forward();
      setState(() => _revealed = true);
      await _controller.reverse();
    } else {
      if (_clicked) return;
      setState(() => _clicked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final baseColor = colorScheme.surfaceContainerHighest;
    final hoverColor = colorScheme.onSurface.withValues(alpha: 0.08);
    final tintColor = widget.isCorrect
        ? AppConfig.success.withValues(alpha: 0.3)
        : AppConfig.error.withValues(alpha: 0.3);

    return CompositedTransformTarget(
      link: MatrixState.pAnyState.layerLinkAndKey(widget.targetId).link,
      child: HoverBuilder(
        builder: (context, hovered) => SizedBox(
          width: widget.shrinkWrap ? null : double.infinity,
          height: widget.shrinkWrap ? null : widget.height,
          child: GestureDetector(
            onTap: _handleTap,
            child: widget.shouldFlip
                ? AnimatedBuilder(
                    animation: _scaleAnim,
                    builder: (context, _) {
                      final scale = _scaleAnim.value;
                      final showContent = scale > 0.05;

                      return Transform.scale(
                        scaleY: scale,
                        child: _CardContainer(
                          height: widget.height,
                          baseColor: baseColor,
                          overlayColor: _revealed
                              ? tintColor
                              : (hovered ? hoverColor : Colors.transparent),
                          shrinkWrap: widget.shrinkWrap,
                          child: Opacity(
                            opacity: showContent ? 1 : 0,
                            child: _revealed ? widget.altChild! : widget.child,
                          ),
                        ),
                      );
                    },
                  )
                : _CardContainer(
                    height: widget.height,
                    baseColor: baseColor,
                    overlayColor: _clicked
                        ? tintColor
                        : (hovered ? hoverColor : Colors.transparent),
                    shrinkWrap: widget.shrinkWrap,
                    child: widget.child,
                  ),
          ),
        ),
      ),
    );
  }
}

class _CardContainer extends StatelessWidget {
  final double height;
  final Color baseColor;
  final Color overlayColor;
  final Widget child;
  final bool shrinkWrap;

  const _CardContainer({
    required this.height,
    required this.baseColor,
    required this.overlayColor,
    required this.child,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: shrinkWrap ? null : height,
      padding: shrinkWrap
          ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)
          : null,
      alignment: shrinkWrap ? null : Alignment.center,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(16),
      ),
      foregroundDecoration: BoxDecoration(
        color: overlayColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
