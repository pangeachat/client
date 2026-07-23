import 'package:flutter/material.dart';

/// Paints a Google-Maps-style teardrop/map-marker silhouette: a circular head
/// (diameter [headDiameter]) with a point extending [pointHeight] below it,
/// converging to a tip at the pin's geographic anchor. Used for mid-tier pins
/// (world-map.instructions.md, "Pin display" — the Figma `Activity pin v3`
/// reference); small-tier pins stay a plain circle.
class TeardropPainter extends CustomPainter {
  final Color color;
  final double headDiameter;
  final double pointHeight;

  const TeardropPainter({
    required this.color,
    required this.headDiameter,
    required this.pointHeight,
  });

  Path _shapePath() {
    final r = headDiameter / 2;
    final centerY = r;
    final bottomY = headDiameter + pointHeight;

    final path = Path();

    // Start at bottom tip
    path.moveTo(0, bottomY);

    // Left lower teardrop curve
    path.cubicTo(
      -r * 0.15,
      bottomY - pointHeight * 0.35,
      -r * 0.95,
      centerY + r * 0.75,
      -r,
      centerY,
    );

    // Top-left -> top-right: actual circular arc
    path.cubicTo(
      -r,
      centerY - r * 0.55,
      -r * 0.55,
      centerY - r,
      0,
      centerY - r,
    );

    path.cubicTo(r * 0.55, centerY - r, r, centerY - r * 0.55, r, centerY);

    // Right lower teardrop curve
    path.cubicTo(
      r * 0.95,
      centerY + r * 0.75,
      r * 0.15,
      bottomY - pointHeight * 0.35,
      0,
      bottomY,
    );

    path.close();

    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Center the shape (built around x=0) in the painter's width.
    canvas.save();
    canvas.translate(size.width / 2, 0);
    final path = _shapePath();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black38
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TeardropPainter old) =>
      old.color != color ||
      old.headDiameter != headDiameter ||
      old.pointHeight != pointHeight;
}
