import 'dart:math';

import 'package:flutter/material.dart';

class SegmentedCircularProgress extends StatelessWidget {
  final List<Segment> segments;
  final double strokeWidth;
  final double gapDegrees;

  const SegmentedCircularProgress({
    super.key,
    required this.segments,
    this.strokeWidth = 4,
    this.gapDegrees = 4,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SegmentedPainter(segments: segments, strokeWidth: strokeWidth),
    );
  }
}

class Segment {
  final double value; // relative value
  final Color color;
  final double opacity;

  Segment(this.value, this.color, {this.opacity = 1.0});
}

class _SegmentedPainter extends CustomPainter {
  final List<Segment> segments;
  final double strokeWidth;
  final double gapFactor = 1.4; // controls extra spacing

  const _SegmentedPainter({
    required this.segments,
    this.strokeWidth = 10, // thinner than before
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;

    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);

    final radius = arcRect.width / 2;
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 🔥 Base cap angle (prevents overlap)
    final baseCapAngle = strokeWidth / radius;

    // 🔥 Extra spacing
    final capAngle = baseCapAngle * gapFactor;

    double startAngle = -pi / 2;

    for (final segment in segments) {
      final rawSweep = (segment.value / total) * 2 * pi;

      final sweep = rawSweep - capAngle;

      if (sweep <= 0) {
        startAngle += rawSweep;
        continue;
      }

      paint.color = segment.color.withAlpha((segment.opacity * 255).ceil());

      canvas.drawArc(arcRect, startAngle + capAngle / 2, sweep, false, paint);

      startAngle += rawSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gapFactor != gapFactor;
  }
}
