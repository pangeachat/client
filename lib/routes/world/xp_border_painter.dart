import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';

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

/// Paints the cluster's XP border: an opaque rounded-rect track around the
/// powerups pill, with a gold stroke that fills from the [anchor] (where the
/// level medal sits) for [progress] (0–1) of the way to the next level,
/// arriving back at the medal at 1.0. The path starts and ends at the anchor
/// so a sub-path extracted from its start grows out from under the badge.
/// The track strokes [trackExtra] wider than the arc, so the arc rides inside
/// it and its adjacent color is the track — never the raw map imagery the
/// ring paints over (#8763, WCAG SC 1.4.11).
class XpBorderPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double stroke;

  /// The corner radius of the rounded rect the pill's content fills, which is
  /// also the track's inner edge: the track is stroked outward from it, so
  /// the two meet exactly at the corners and nothing shows through between
  /// them. The path's own radius follows from this and the stroke.
  final double innerRadius;
  final XpBorderAnchor anchor;

  /// How much wider the unfilled track strokes than the [progressColor] arc
  /// riding inside it. Callers keeping the pill clear of the ring pad by
  /// stroke + trackExtra.
  static const double trackExtra = 4.0;

  /// The unfilled track for [theme]: `goldTrack`, a dark gold in light and a
  /// mid gold in dark, opaque so the arc's adjacent colour is the track and
  /// not the map (#8763). It clears 3:1 against the tiles it rides over in
  /// both themes; see xp_ring_contrast_test.
  static Color trackColorFor(ThemeData theme) => theme.pangea.goldTrack;

  /// The filled arc for [theme]: the bright gold in light, and in dark the
  /// paler `goldFixed`, the tone that still clears 3:1 on the mid-gold track
  /// (the bright gold measures 2.64:1 on it).
  static Color arcColorFor(ThemeData theme) =>
      theme.brightness == Brightness.light
      ? theme.pangea.goldFixedDim
      : theme.pangea.goldFixed;

  XpBorderPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.stroke,
    required this.innerRadius,
    this.anchor = XpBorderAnchor.bottomCenter,
  });

  Path _border(Size size) {
    // The path is the track's centreline: half the track's width in from the
    // edge, with a corner radius half the track's width out from the content
    // corner, so the track's inner edge lands on the content's rounded rect.
    final inset = (stroke + trackExtra) / 2;
    final r = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    final rad = innerRadius + inset;
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
        ..strokeWidth = stroke + trackExtra
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

  @override
  bool shouldRepaint(XpBorderPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.stroke != stroke ||
      old.innerRadius != innerRadius ||
      old.anchor != anchor;
}
