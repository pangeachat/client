import 'package:flutter/material.dart';

/// Where the XP progress starts and ends on the pill's border — the spot the
/// level medal overhangs, so the gold grows out from under the badge and
/// arrives back at it at 1.0.
enum XpBorderAnchor {
  /// The web cluster's vertical pill: the medal sits at the base.
  bottomCenter,

  /// The narrow analytics bar's horizontal pill: the medal overhangs the left
  /// end; progress emerges from the badge's top, sweeps clockwise around the
  /// pill, and meets at the badge's bottom.
  leftCenter,
}

/// Paints the cluster's XP border: a gray rounded-rect track around the powerups
/// pill, with a gold stroke that fills from the [anchor] (where the level medal
/// sits) for [progress] (0–1) of the way to the next level, arriving back at
/// the medal at 1.0. The path starts and ends at the anchor so a sub-path
/// extracted from its start grows out from under the badge.
class XpBorderPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;

  /// Painted as a slightly wider stroke *beneath* the ring, so the ring has a
  /// defined edge against whatever map tile happens to be behind it.
  ///
  /// The ring is drawn outside the pill's opaque fill, straight onto raw OSM
  /// tiles. Against light-mode cartography the gold measured 1.04–1.66:1 and
  /// filled-vs-unfilled 1.07–1.42:1 — the progress could not be read at all
  /// (#8763). Pass the theme's `onSurface`: dark in light mode, where the
  /// tiles are pale and the arc needs separating from them; light in dark
  /// mode, where the tiles invert and it is the grey track that goes faint.
  final Color casingColor;
  final double stroke;
  final double radius;
  final XpBorderAnchor anchor;

  XpBorderPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.casingColor,
    required this.stroke,
    required this.radius,
    this.anchor = XpBorderAnchor.bottomCenter,
  });

  Path _border(Size size) {
    final r = Rect.fromLTRB(
      stroke / 2,
      stroke / 2,
      size.width - stroke / 2,
      size.height - stroke / 2,
    );
    final rad = radius;
    final arc = Radius.circular(rad);
    switch (anchor) {
      case XpBorderAnchor.bottomCenter:
        final cx = r.center.dx;
        return Path()
          ..moveTo(cx, r.bottom)
          ..lineTo(r.left + rad, r.bottom)
          ..arcToPoint(
            Offset(r.left, r.bottom - rad),
            radius: arc,
            clockwise: true,
          )
          ..lineTo(r.left, r.top + rad)
          ..arcToPoint(
            Offset(r.left + rad, r.top),
            radius: arc,
            clockwise: true,
          )
          ..lineTo(r.right - rad, r.top)
          ..arcToPoint(
            Offset(r.right, r.top + rad),
            radius: arc,
            clockwise: true,
          )
          ..lineTo(r.right, r.bottom - rad)
          ..arcToPoint(
            Offset(r.right - rad, r.bottom),
            radius: arc,
            clockwise: true,
          )
          ..lineTo(cx, r.bottom);
      case XpBorderAnchor.leftCenter:
        final cy = r.center.dy;
        // Visually clockwise from the left-center: up past the badge's top,
        // across the top edge, down the right end, back along the bottom —
        // meeting at the badge's bottom.
        return Path()
          ..moveTo(r.left, cy)
          ..lineTo(r.left, r.top + rad)
          ..arcToPoint(
            Offset(r.left + rad, r.top),
            radius: arc,
            clockwise: true,
          )
          ..lineTo(r.right - rad, r.top)
          ..arcToPoint(
            Offset(r.right, r.top + rad),
            radius: arc,
            clockwise: true,
          )
          ..lineTo(r.right, r.bottom - rad)
          ..arcToPoint(
            Offset(r.right - rad, r.bottom),
            radius: arc,
            clockwise: true,
          )
          ..lineTo(r.left + rad, r.bottom)
          ..arcToPoint(
            Offset(r.left, r.bottom - rad),
            radius: arc,
            clockwise: true,
          )
          ..lineTo(r.left, cy);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _border(size);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + _casingWidth * 2
        ..color = casingColor,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * p),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = progressColor,
    );
  }

  /// How far the casing shows on each side of the ring. One logical pixel is
  /// enough to define the edge and keeps the ring's weight visually unchanged.
  static const double _casingWidth = 1.0;

  @override
  bool shouldRepaint(XpBorderPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.casingColor != casingColor ||
      old.stroke != stroke ||
      old.radius != radius ||
      old.anchor != anchor;
}
