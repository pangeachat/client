import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The narrow bar's level badge: the Figma hexagon (pointy left/right, flat
/// top/bottom) with a darker gold border and the level number centered —
/// unlike the web cluster's tailed shield medal, which hangs its number low
/// and carries the notched ribbon bottom the mobile design drops. Same
/// semantics contract as [ClusterLevelMedal] (named button, tap opens Level),
/// and the same state treatment: hover and the open Level panel deepen the
/// badge's own gold instead of putting a wash behind or around it (#8067).
class HexLevelBadge extends StatefulWidget {
  final int level;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double fontSize;

  /// Whether the Level analytics panel is open — then the badge stays in its
  /// deepened gold, the sticky counterpart of hover (#8062, #8067).
  final bool selected;

  const HexLevelBadge({
    super.key,
    required this.level,
    required this.onTap,
    this.width = 48.0,
    this.height = 42.0,
    this.fontSize = 18.0,
    this.selected = false,
  });

  @override
  State<HexLevelBadge> createState() => _HexLevelBadgeState();
}

class _HexLevelBadgeState extends State<HexLevelBadge> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final label = '${L10n.of(context).level} ${widget.level}';
    final lit = _hovered || widget.selected;
    final fill = lit
        ? AppConfig.goldHighlightByTheme(context)
        : AppConfig.goldByTheme(context);
    // The outline is always a step darker than whatever the fill is, so the
    // lit badge deepens as one mark.
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
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: CustomPaint(
              size: Size(widget.width, widget.height),
              painter: HexBadgePainter(fill: fill, border: border),
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: Center(
                  child: Text(
                    '${widget.level}',
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
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

/// Builds the badge hexagon inside [size]: vertices at the horizontal extremes,
/// flat top and bottom edges (the Figma component).
///
/// The path is inset by half [hexBadgeStrokeWidth] on every side so the
/// centered outline — and the round joins, which reach exactly half a stroke
/// past each vertex — paint **entirely inside** the badge's own box. Nothing
/// may bleed outside: the narrow analytics bar sits the badge flush against
/// the left edge of a shimmering `Stack`, and `Shimmer`'s mask covers only the
/// render box, so an escaping pixel keeps its real gold while the rest of the
/// cluster is gray (#7801). [XpBorderPainter] insets for the same reason.
@visibleForTesting
Path hexBadgePath(Size size) {
  final d = hexBadgeStrokeWidth / 2;
  final w = size.width - hexBadgeStrokeWidth;
  final h = size.height - hexBadgeStrokeWidth;
  return Path()
    ..moveTo(d, d + h / 2)
    ..lineTo(d + w * 0.25, d)
    ..lineTo(d + w * 0.75, d)
    ..lineTo(d + w, d + h / 2)
    ..lineTo(d + w * 0.75, d + h)
    ..lineTo(d + w * 0.25, d + h)
    ..close();
}

/// Width of the badge's darker-gold outline.
const double hexBadgeStrokeWidth = 2.5;

/// Paints the badge hexagon ([hexBadgePath]) with a gold fill and a darker gold
/// outline (the Figma component). Public so tests can read the gold the badge
/// is actually wearing — that color IS the hover / open-panel state (#8067).
class HexBadgePainter extends CustomPainter {
  final Color fill;
  final Color border;

  const HexBadgePainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = hexBadgePath(size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hexBadgeStrokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(HexBadgePainter old) =>
      old.fill != fill || old.border != border;
}
