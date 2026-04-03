import 'package:flutter/material.dart';

class CutoutBackgroundPainter extends CustomPainter {
  final Rect? holeRect;
  final Color backgroundColor;
  final double borderRadius;
  final double padding;

  CutoutBackgroundPainter({
    this.holeRect,
    Color? backgroundColor,
    this.borderRadius = 0.0,
    this.padding = 6.0,
  }) : backgroundColor = backgroundColor ?? Colors.black.withAlpha(180);

  @override
  void paint(Canvas canvas, Size size) {
    final holeRect = this.holeRect;
    if (holeRect == null) return;
    final paint = Paint()..color = backgroundColor;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            holeRect.left - padding,
            holeRect.top - padding,
            holeRect.width + 2 * padding,
            holeRect.height + 2 * padding,
          ),
          Radius.circular(borderRadius),
        ),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
