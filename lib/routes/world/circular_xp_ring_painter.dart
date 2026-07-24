import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paints the collapsed avatar's XP ring: a full gray circular track with a
/// gold arc filling clockwise from the level badge for [progress] (0-1) of the way to
/// the next level. The cluster's `XpBorderPainter` traces the powerups pill's
/// rounded-rect outline instead, so the circular avatar needs this simpler
/// circular counterpart rather than reusing it as-is.
class CircularXpRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double stroke;

  const CircularXpRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.drawArc(
      rect,
      -2 * math.pi / 3,
      2 * math.pi * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = progressColor,
    );
  }

  @override
  bool shouldRepaint(CircularXpRingPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.stroke != stroke;
}
