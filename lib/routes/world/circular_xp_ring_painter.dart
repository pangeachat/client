import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/xp_border_painter.dart';

/// Paints the collapsed avatar's XP ring: a full opaque circular track with a
/// gold arc filling clockwise from the level badge for [progress] (0-1) of the way to
/// the next level. The cluster's `XpBorderPainter` traces the powerups pill's
/// rounded-rect outline instead, so the circular avatar needs this simpler
/// circular counterpart rather than reusing it as-is. Like its sibling, the
/// track strokes [XpBorderPainter.trackExtra] wider than the arc so the arc
/// rides inside it and never meets raw map imagery (#8763, WCAG SC 1.4.11).
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

    // The widened track keeps the arc's centerline (and so the avatar and
    // badge layout) untouched, overshooting the paint box by trackExtra / 2 on
    // each side instead: outward over the map like the badge celebration this
    // Stack already paints with Clip.none, inward under the opaque avatar.
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + XpBorderPainter.trackExtra
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
