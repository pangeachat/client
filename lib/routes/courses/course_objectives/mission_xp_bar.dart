import 'package:flutter/material.dart';

import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';

/// A Mission's XP as a horizontal bar (#9559), on the course page's Mission
/// card: [MissionXpRing]-style segments laid end to end from the start
/// edge over a [trackColor] track, clamped so together they never pass the
/// end. Thin [gapColor] cuts keep neighbouring golds apart, as on the ring.
class MissionXpBar extends StatelessWidget {
  final List<MissionXpRingSegment> segments;
  final Color trackColor;
  final Color gapColor;
  final double height;

  const MissionXpBar({
    required this.segments,
    required this.trackColor,
    required this.gapColor,
    this.height = 12.0,
    super.key,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: _MissionXpBarPainter(
        segments: segments,
        trackColor: trackColor,
        gapColor: gapColor,
        textDirection: Directionality.of(context),
      ),
    ),
  );
}

class _MissionXpBarPainter extends CustomPainter {
  final List<MissionXpRingSegment> segments;
  final Color trackColor;
  final Color gapColor;
  final TextDirection textDirection;

  _MissionXpBarPainter({
    required this.segments,
    required this.trackColor,
    required this.gapColor,
    required this.textDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(size.height / 2),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(bounds, Paint()..color = trackColor);

    final rtl = textDirection == TextDirection.rtl;
    var start = 0.0;
    var remaining = 1.0;
    final cuts = <double>[];
    for (final segment in segments) {
      final fraction = segment.fraction.clamp(0.0, remaining);
      if (fraction <= 0) continue;
      final width = fraction * size.width;
      final left = rtl ? size.width - start - width : start;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, width, size.height),
        Paint()..color = segment.color,
      );
      start += width;
      remaining -= fraction;
      cuts.add(start);
    }
    // Cuts between neighbouring segments, never after the last one.
    if (cuts.length > 1) {
      final cut = Paint()
        ..color = gapColor
        ..strokeWidth = 2.0;
      for (final x in cuts.sublist(0, cuts.length - 1)) {
        final dx = rtl ? size.width - x : x;
        canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), cut);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MissionXpBarPainter old) =>
      old.trackColor != trackColor ||
      old.gapColor != gapColor ||
      old.textDirection != textDirection ||
      old.segments.length != segments.length ||
      [
        for (var i = 0; i < segments.length; i++)
          old.segments[i].fraction != segments[i].fraction ||
              old.segments[i].color != segments[i].color,
      ].any((changed) => changed);
}
