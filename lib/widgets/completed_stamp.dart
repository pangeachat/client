import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The completed mark: a white disc with a double ring and a check, in the
/// mark gold — the same symbol on an activity's card and its map pin — with
/// "×N" hung off it once the learner has finished the activity more than once.
class CompletedStamp extends StatelessWidget {
  final double size;
  final int times;

  const CompletedStamp({required this.size, this.times = 1, super.key});

  /// The stamp's disc, under its rings and check — white in both themes.
  static const Color paper = Colors.white;

  /// The gold of the stamp's rings and check: the mark gold tuned for a light
  /// surface whatever the theme, because it is always drawn on the white
  /// [paper]. The dark theme's mark gold is a light tone that would wash out
  /// there.
  static Color get ink => PangeaColors.of(Brightness.light).goldGraphic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = times > 1
        ? L10n.of(context).completedTimes(times)
        : L10n.of(context).activityCompleted;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: size + (times > 1 ? size * 0.35 : 0),
          height: size + (times > 1 ? size * 0.3 : 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 3.0,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _CompletedStampPainter(ink: ink, paper: paper),
                ),
              ),
              if (times > 1)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 1.0,
                    ),
                    decoration: BoxDecoration(
                      color: theme.pangea.goldFixedDim,
                      borderRadius: BorderRadius.circular(999.0),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      '×$times',
                      style: TextStyle(
                        color: theme.pangea.onGoldFixed,
                        fontSize: (size * 0.36).clamp(8.0, 12.0),
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedStampPainter extends CustomPainter {
  final Color ink;
  final Color paper;

  _CompletedStampPainter({required this.ink, required this.paper});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = paper);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = ink;
    canvas.drawCircle(c, r * 0.86, stroke..strokeWidth = r * 0.17);
    canvas.drawCircle(c, r * 0.6, stroke..strokeWidth = r * 0.1);
    final check = Path()
      ..moveTo(c.dx - r * 0.3, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.08, c.dy + r * 0.24)
      ..lineTo(c.dx + r * 0.32, c.dy - r * 0.2);
    canvas.drawPath(
      check,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = ink
        ..strokeWidth = r * 0.17
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CompletedStampPainter old) =>
      old.ink != ink || old.paper != paper;
}
