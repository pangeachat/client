import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Tracks active growth animations for offset calculation
class GrowthAnimationTracker {
  static int _activeCount = 0;

  static int get activeCount => _activeCount;

  static double? startAnimation() {
    if (_activeCount >= 5) return null;
    final index = _activeCount;
    _activeCount++;
    if (index == 0) return 0;
    final side = index.isOdd ? 1 : -1;
    return side * ((index + 1) ~/ 2) * 20.0;
  }

  static void endAnimation() {
    _activeCount = (_activeCount - 1).clamp(0, 999);
  }
}

class GrowthAnimation extends StatefulWidget {
  final String targetID;
  final ConstructLevelEnum level;

  const GrowthAnimation({
    super.key,
    required this.targetID,
    required this.level,
  });

  @override
  State<GrowthAnimation> createState() => _GrowthAnimationState();
}

class _GrowthAnimationState extends State<GrowthAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final double? _horizontalOffset;
  late final double _wiggleAmplitude;
  late final double _wiggleFrequency;
  final Random _random = Random();

  static const _durationMs = 1600;
  static const _riseDistance = 72.0;

  @override
  void initState() {
    super.initState();
    _horizontalOffset = GrowthAnimationTracker.startAnimation();
    _wiggleAmplitude = 4.0 + _random.nextDouble() * 4.0;
    _wiggleFrequency = 1.5 + _random.nextDouble() * 1.0;

    _controller =
        AnimationController(
            duration: const Duration(milliseconds: _durationMs),
            vsync: this,
          )
          ..forward().then((_) {
            if (mounted) {
              MatrixState.pAnyState.closeOverlay(widget.targetID);
            }
          });
  }

  @override
  void dispose() {
    GrowthAnimationTracker.endAnimation();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_horizontalOffset == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final dy = -_riseDistance * Curves.easeOut.transform(t);
        final opacity = t < 0.5 ? t * 2 : (1.0 - t) * 2;
        final wiggle = sin(t * pi * _wiggleFrequency) * _wiggleAmplitude;
        return Transform.translate(
          offset: Offset(_horizontalOffset + wiggle, dy),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: widget.level.icon(24),
          ),
        );
      },
    );
  }
}
