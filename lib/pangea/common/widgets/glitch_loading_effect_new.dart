import 'package:flutter/material.dart';

import 'package:animated_glitch/animated_glitch.dart';

/// A simple glitch loading effect wrapper
class GlitchLoadingEffect extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const GlitchLoadingEffect({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<GlitchLoadingEffect> createState() => _GlitchLoadingEffectState();
}

class _GlitchLoadingEffectState extends State<GlitchLoadingEffect> {
  late AnimatedGlitchController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimatedGlitchController(
      frequency: const Duration(milliseconds: 200),
      level: 2.5,
      distortionShift: const DistortionShift(count: 2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return AnimatedGlitch(
      showColorChannels: true,
      showDistortions: true,
      controller: _controller,
      child: widget.child,
    );
  }
}

class GlitchShimmerLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const GlitchShimmerLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<GlitchShimmerLoader> createState() => _GlitchShimmerLoaderState();
}

class _GlitchShimmerLoaderState extends State<GlitchShimmerLoader> {
  late AnimatedGlitchController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimatedGlitchController(
      frequency: const Duration(milliseconds: 300),
      level: 1.0,
      distortionShift: const DistortionShift(count: 5),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // gradient background with logo
    final child = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withAlpha(180),
            theme.colorScheme.primaryContainer.withAlpha(160),
          ],
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.4,
          child: Image.asset(
            'assets/pangea/PangeaChat_Glow_Logo.png',
            width: widget.width * 0.6,
            height: widget.height * 0.6,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );

    // non-shader version of AnimatedGlitch, shaders problematic on web
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12.0),
        child: AnimatedGlitch(
          controller: _controller,
          showColorChannels: true,
          showDistortions: true,
          child: child,
        ),
      ),
    );
  }
}
