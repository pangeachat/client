import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class ShimmerBackground extends StatefulWidget {
  final Widget child;
  final Color shimmerColor;
  final Color? baseColor;
  final bool enabled;
  final BorderRadius? borderRadius;

  const ShimmerBackground({
    super.key,
    required this.child,
    this.shimmerColor = AppConfig.goldLight,
    this.baseColor,
    this.enabled = true,
    this.borderRadius,
  });

  @override
  State<ShimmerBackground> createState() => _ShimmerBackgroundState();
}

class _ShimmerBackgroundState extends State<ShimmerBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ShimmerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final borderRadius =
        widget.borderRadius ?? BorderRadius.circular(AppConfig.borderRadius);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.shimmerColor
                          .withValues(alpha: _animation.value),
                      borderRadius: borderRadius,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
