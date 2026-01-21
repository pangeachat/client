import 'dart:math';

import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class GrowthAnimation extends StatefulWidget {
  final String targetID;
  final ConstructLevelEnum level;
  final double horizontalOffset;
  final VoidCallback? onComplete;

  final int durationMs;
  final double riseDistance;

  const GrowthAnimation({
    super.key,
    required this.targetID,
    required this.level,
    this.horizontalOffset = 0,
    this.onComplete,
    this.durationMs = 1600,
    this.riseDistance = 72,
  });

  @override
  State<GrowthAnimation> createState() => _GrowthAnimationState();
}

class _GrowthAnimationState extends State<GrowthAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  late final Random _random;
  late final double _wiggleAmplitude;
  late final double _wiggleFrequency;
  late final int _actualDuration;

  @override
  void initState() {
    super.initState();

    // Create random variations for animation
    _random = Random();
    _wiggleAmplitude = 4.0 + _random.nextDouble() * 4.0;
    _wiggleFrequency = 1.5 + _random.nextDouble() * 1.0;
    _actualDuration = widget.durationMs + (_random.nextInt(400) - 200);

    _controller = AnimationController(
      duration: Duration(milliseconds: _actualDuration),
      vsync: this,
    );

    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward().then((_) {
      if (!mounted) return;
      MatrixState.pAnyState
          .closeOverlay("${widget.targetID}_growth_${widget.hashCode}");
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, child) {
          final clampedT = _progress.value.clamp(0.0, 1.0);
          final dy = -widget.riseDistance * clampedT;
          final opacity = clampedT < 0.5 ? clampedT * 2 : (1.0 - clampedT) * 2;

          final wiggle =
              sin(clampedT * pi * _wiggleFrequency) * _wiggleAmplitude;

          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(widget.horizontalOffset + wiggle, dy),
              child: widget.level.icon(24),
            ),
          );
        },
      ),
    );
  }
}
