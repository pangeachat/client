import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';

/// The colours of a Mission's XP ring, shared by every surface that draws one
/// (the course page's Mission card, the Learning Objectives list and detail).
/// Bright gold only reads against something dark, so the empty band is dark in
/// both themes and the XP golds stay bright: amber for chats, gold for goals,
/// pale gold for practice — apart by lightness rather than hue alone.
class MissionRingPalette {
  final Color track;
  final Color chat;
  final Color goals;
  final Color practice;

  const MissionRingPalette._({
    required this.track,
    required this.chat,
    required this.goals,
    required this.practice,
  });

  factory MissionRingPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final goals = theme.pangea.goldFixedDim;
    final hsl = HSLColor.fromColor(goals);
    return MissionRingPalette._(
      track: theme.brightness == Brightness.light
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.18),
              scheme.inverseSurface,
            )
          : scheme.surfaceContainerHighest,
      chat: hsl.withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0)).toColor(),
      goals: goals,
      practice: theme.pangea.goldFixed,
    );
  }
}

/// One coloured run of a [MissionXpRing]: its share of the threshold.
class MissionXpRingSegment {
  final double fraction;
  final Color color;

  const MissionXpRingSegment({required this.fraction, required this.color});
}

/// A ring that fills clockwise from the top with [segments] laid end to end
/// over a [trackColor] track. The segments are clamped so together they never
/// pass a full turn; thin [gapColor] cuts between them keep neighbouring
/// shades apart when they sit close in lightness.
class MissionXpRing extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final List<MissionXpRingSegment> segments;
  final Color trackColor;
  final Color gapColor;
  final Widget? child;

  const MissionXpRing({
    required this.size,
    required this.strokeWidth,
    required this.segments,
    required this.trackColor,
    required this.gapColor,
    this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _MissionXpRingPainter(
        strokeWidth: strokeWidth,
        segments: segments,
        trackColor: trackColor,
        gapColor: gapColor,
      ),
      child: Center(child: child),
    ),
  );
}

class _MissionXpRingPainter extends CustomPainter {
  final double strokeWidth;
  final List<MissionXpRingSegment> segments;
  final Color trackColor;
  final Color gapColor;

  _MissionXpRingPainter({
    required this.strokeWidth,
    required this.segments,
    required this.trackColor,
    required this.gapColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - strokeWidth) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = trackColor);

    var start = -math.pi / 2;
    var remaining = 1.0;
    final drawn = <double>[];
    for (final segment in segments) {
      final fraction = segment.fraction.clamp(0.0, remaining);
      if (fraction <= 0) continue;
      final sweep = fraction * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, false, paint..color = segment.color);
      start += sweep;
      remaining -= fraction;
      drawn.add(start);
    }
    // Cuts between neighbouring segments (not after the last one, unless the
    // ring is full and the last meets the first).
    if (drawn.length > 1 || remaining <= 0) {
      final cuts = remaining <= 0 ? drawn : drawn.sublist(0, drawn.length - 1);
      final cut = Paint()
        ..color = gapColor
        ..strokeWidth = 2.0;
      final inner = rect.width / 2 - strokeWidth / 2;
      final outer = rect.width / 2 + strokeWidth / 2;
      for (final angle in cuts) {
        final dir = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          rect.center + dir * inner,
          rect.center + dir * outer,
          cut,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MissionXpRingPainter old) =>
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor ||
      old.gapColor != gapColor ||
      old.segments.length != segments.length ||
      [
        for (var i = 0; i < segments.length; i++)
          old.segments[i].fraction != segments[i].fraction ||
              old.segments[i].color != segments[i].color,
      ].any((changed) => changed);
}
