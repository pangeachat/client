import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';

/// One activity goal's mark (#9420 prototype): a diamond — gold and filled
/// once earned, an outline while open. Every goal row, the in-session goal
/// header and its fly-in use it, so a goal reads as one thing everywhere and
/// never as a star (a Mission), the double-ring stamp (a finished activity) or
/// a sparkle (XP).
///
/// The earned diamond fills with the bright gold and edges in [color] (the
/// darker mark gold by default), so it clears 3:1 on a light surface while the
/// fill stays bright. An open one is the outline alone, in [emptyColor].
class GoalDiamond extends StatelessWidget {
  final bool earned;
  final double size;

  /// The edge of an earned diamond; null uses the theme's mark gold.
  final Color? color;

  /// The fill of an earned diamond; null uses the theme's bright gold.
  final Color? fillColor;

  /// The outline of an open diamond; null uses `onSurfaceVariant`.
  final Color? emptyColor;

  const GoalDiamond({
    required this.earned,
    required this.size,
    this.color,
    this.fillColor,
    this.emptyColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edge = earned
        ? (color ?? theme.pangea.goldGraphic)
        : (emptyColor ?? theme.colorScheme.onSurfaceVariant);
    final fill = earned ? (fillColor ?? theme.pangea.goldFixedDim) : null;
    return CustomPaint(
      size: Size.square(size),
      painter: _DiamondPainter(edge: edge, fill: fill),
    );
  }
}

class _DiamondPainter extends CustomPainter {
  final Color edge;
  final Color? fill;

  _DiamondPainter({required this.edge, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = (size.shortestSide * 0.12).clamp(1.0, 3.0);
    // A slightly tall diamond inset by half the stroke so the edge isn't
    // clipped.
    final inset = stroke / 2 + size.width * 0.08;
    final path = Path()
      ..moveTo(size.width / 2, stroke / 2)
      ..lineTo(size.width - inset, size.height / 2)
      ..lineTo(size.width / 2, size.height - stroke / 2)
      ..lineTo(inset, size.height / 2)
      ..close();
    final fill = this.fill;
    if (fill != null) canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(covariant _DiamondPainter old) =>
      old.edge != edge || old.fill != fill;
}
