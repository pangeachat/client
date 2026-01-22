import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _GrowthItem {
  final ConstructLevelEnum level;
  final double horizontalOffset;
  final double wiggleAmplitude;
  final double wiggleFrequency;
  final int delayMs;

  _GrowthItem({
    required this.level,
    required this.horizontalOffset,
    required this.wiggleAmplitude,
    required this.wiggleFrequency,
    required this.delayMs,
  });
}

class GrowthAnimation extends StatefulWidget {
  final String targetID;
  final Map<ConstructLevelEnum, int> levelCounts;
  final int itemDurationMs;
  final double riseDistance;

  const GrowthAnimation({
    super.key,
    required this.targetID,
    required this.levelCounts,
    this.itemDurationMs = 1600,
    this.riseDistance = 72,
  });

  @override
  State<GrowthAnimation> createState() => _GrowthAnimationState();
}

class _GrowthAnimationState extends State<GrowthAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_GrowthItem> _items;
  late final int _totalDurationMs;
  final Random _random = Random();

  static const int _staggerDelayMs = 50;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
    final maxDelay = _items.isEmpty ? 0 : _items.last.delayMs;
    _totalDurationMs = maxDelay + widget.itemDurationMs;

    _controller = AnimationController(
      duration: Duration(milliseconds: _totalDurationMs),
      vsync: this,
    );

    _controller.forward().then((_) {
      if (!mounted) return;
      MatrixState.pAnyState.closeOverlay("${widget.targetID}_growth");
    });
  }

  List<_GrowthItem> _buildItems() {
    final items = <_GrowthItem>[];
    int index = 0;

    for (final level in [
      ConstructLevelEnum.seeds,
      ConstructLevelEnum.greens,
      ConstructLevelEnum.flowers,
    ]) {
      final count = widget.levelCounts[level] ?? 0;
      for (int i = 0; i < count; i++) {
        final side = index % 2 == 0 ? 1 : -1;
        final distance = ((index + 1) ~/ 2) * 30.0;

        items.add(
          _GrowthItem(
            level: level,
            horizontalOffset: side * distance,
            wiggleAmplitude: 4.0 + _random.nextDouble() * 4.0,
            wiggleFrequency: 1.5 + _random.nextDouble() * 1.0,
            delayMs: index * _staggerDelayMs,
          ),
        );
        index++;
      }
    }
    return items;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            clipBehavior: Clip.none,
            children: _items.map(_buildItem).toList(),
          );
        },
      ),
    );
  }

  Widget _buildItem(_GrowthItem item) {
    final elapsedMs = _controller.value * _totalDurationMs;
    final itemElapsedMs =
        (elapsedMs - item.delayMs).clamp(0.0, widget.itemDurationMs.toDouble());
    final t = (itemElapsedMs / widget.itemDurationMs).clamp(0.0, 1.0);

    if (t <= 0) return const SizedBox.shrink();

    final curvedT = Curves.easeOut.transform(t);
    final dy = -widget.riseDistance * curvedT;
    final opacity = t < 0.5 ? t * 2 : (1.0 - t) * 2;
    final wiggle = sin(t * pi * item.wiggleFrequency) * item.wiggleAmplitude;

    return Transform.translate(
      offset: Offset(item.horizontalOffset + wiggle, dy),
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: item.level.icon(24),
      ),
    );
  }
}
