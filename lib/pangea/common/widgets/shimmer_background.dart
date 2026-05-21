import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class ShimmerBackground extends StatefulWidget {
  final Widget child;
  final Color shimmerColor;
  final bool enabled;
  final BorderRadius? borderRadius;
  final Duration delayBetweenPulses;
  final double maxOpacity;

  const ShimmerBackground({
    super.key,
    required this.child,
    this.shimmerColor = AppConfig.goldLight,
    this.enabled = true,
    this.borderRadius,
    this.delayBetweenPulses = Duration.zero,
    this.maxOpacity = 0.3,
  });

  @override
  State<ShimmerBackground> createState() => _ShimmerBackgroundState();
}

class _ShimmerBackgroundState extends State<ShimmerBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  static const Duration pulseDuration = Duration(milliseconds: 1000);

  bool _disposed = false;
  bool _isPulsing = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(duration: pulseDuration, vsync: this);

    _animation = Tween<double>(
      begin: 0.0,
      end: widget.maxOpacity,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.enabled) {
      _startPulsing();
    }
  }

  void _startPulsing() {
    if (_disposed || !mounted) return;

    if (widget.delayBetweenPulses == Duration.zero) {
      _controller.repeat(reverse: true);
      return;
    }

    _pulseLoop();
  }

  Future<void> _pulseLoop() async {
    if (_isPulsing) return;

    _isPulsing = true;

    try {
      while (mounted &&
          !_disposed &&
          widget.enabled &&
          widget.delayBetweenPulses != Duration.zero) {
        await _controller.forward();

        if (!mounted || _disposed || !widget.enabled) break;

        await _controller.reverse();

        if (!mounted || _disposed || !widget.enabled) break;

        await Future.delayed(widget.delayBetweenPulses);

        if (!mounted || _disposed || !widget.enabled) break;
      }
    } finally {
      _isPulsing = false;
    }
  }

  @override
  void didUpdateWidget(ShimmerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.enabled == oldWidget.enabled) return;

    if (widget.enabled) {
      _startPulsing();
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _disposed = true;

    _controller.stop();
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
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.shimmerColor.withValues(
                        alpha: _animation.value,
                      ),
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
