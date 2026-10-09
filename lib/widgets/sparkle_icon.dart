import 'package:flutter/material.dart';

/// The four-point sparkle that marks one orchestrator-awarded activity goal
/// (#9439). The five-point star is reserved for Learning Objectives: a star is
/// a completed Mission, a sparkle is a goal inside one activity, and the two
/// never share a glyph (quests.instructions.md, "Stars and sparkles").
///
/// Drawn with Flutter's own [StarBorder], so there is no icon-font glyph or
/// asset to keep in step. Sized like an [Icon]: the shape is inset so its ink
/// matches a Material icon's at the same nominal [size], and the two sit level
/// in a row.
class SparkleIcon extends StatelessWidget {
  final double size;
  final Color color;

  /// A filled sparkle is an earned goal; an outline is one still to earn.
  final bool filled;

  const SparkleIcon({
    required this.size,
    required this.color,
    this.filled = true,
    super.key,
  });

  /// The one sparkle shape, shared by every size so the proportions never
  /// drift between a card's 12px row and the goal header's 28px mark.
  static StarBorder shape({BorderSide side = BorderSide.none}) => StarBorder(
    points: 4,
    innerRadiusRatio: 0.38,
    pointRounding: 0.3,
    side: side,
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Padding(
      // A Material icon paints about 80% of its box; the inset keeps a
      // sparkle from reading larger than the star it replaced.
      padding: EdgeInsets.all(size * 0.08),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: filled ? color : null,
          shape: shape(
            side: filled
                ? BorderSide.none
                : BorderSide(color: color, width: (size / 12).clamp(1.0, 2.5)),
          ),
        ),
      ),
    ),
  );
}
