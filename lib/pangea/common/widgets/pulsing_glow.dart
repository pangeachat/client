import 'package:flutter/material.dart';

/// A soft glow that breathes out from behind [child] to draw the eye to the
/// one thing to press. Still when [enabled] is false or the platform asks for
/// reduced motion.
class PulsingGlow extends StatefulWidget {
  final bool enabled;
  final Color color;
  final BorderRadius borderRadius;
  final Widget child;

  const PulsingGlow({
    required this.enabled,
    required this.color,
    required this.borderRadius,
    required this.child,
    super.key,
  });

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PulsingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.enabled && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = Curves.easeOut.transform(_controller.value);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _controller.isAnimating
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.45 * (1 - t)),
                    spreadRadius: 10.0 * t,
                  ),
                ]
              : null,
        ),
        child: child,
      );
    },
  );
}
