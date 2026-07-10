import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The narrow bar's level badge: the Figma hexagon (pointy left/right, flat
/// top/bottom) with a darker gold border and the level number centered —
/// unlike the web cluster's tailed shield medal, which hangs its number low
/// and carries the notched ribbon bottom the mobile design drops. Same
/// semantics contract as [ClusterLevelMedal] (named button, tap opens Level).
class HexLevelBadge extends StatelessWidget {
  final int level;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double fontSize;

  const HexLevelBadge({
    super.key,
    required this.level,
    required this.onTap,
    this.width = 48.0,
    this.height = 42.0,
    this.fontSize = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    final label = '${L10n.of(context).level} $level';
    final fill = AppConfig.goldByTheme(context);
    final hsl = HSLColor.fromColor(fill);
    final border = hsl
        .withLightness((hsl.lightness * 0.72).clamp(0.0, 1.0))
        .toColor();
    return Tooltip(
      message: label,
      // Semantics below names this; exclude the Tooltip so the label isn't
      // announced twice.
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        container: true,
        excludeSemantics: true,
        // Expose the tap on the announced node for assistive tech (#7185).
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CustomPaint(
            size: Size(width, height),
            painter: _HexBadgePainter(fill: fill, border: border),
            child: SizedBox(
              width: width,
              height: height,
              child: Center(
                child: Text(
                  '$level',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the badge hexagon: vertices at the horizontal extremes, flat top and
/// bottom edges, gold fill with a darker gold outline (the Figma component).
class _HexBadgePainter extends CustomPainter {
  final Color fill;
  final Color border;

  const _HexBadgePainter({required this.fill, required this.border});

  Path _hex(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, h / 2)
      ..lineTo(w * 0.25, 0)
      ..lineTo(w * 0.75, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w * 0.75, h)
      ..lineTo(w * 0.25, h)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _hex(size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_HexBadgePainter old) =>
      old.fill != fill || old.border != border;
}
