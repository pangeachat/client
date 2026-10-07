import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/customized_svg.dart';

/// Where the level number is drawn relative to the shield.
enum LevelNumberPlacement {
  /// Overlaid on the shield — the learner's own level, drawn large enough that
  /// the digits fit inside the mark ([ClusterLevelMedal]).
  inside,

  /// Beside the shield, the same `icon + count` shape the star total uses. The
  /// inline chips are ~18px tall, where a number inside is cramped and gets
  /// worse with two digits or at large OS text sizes (#8918).
  trailing,
}

/// The gold ribbon/shield that represents a learner's level across the app —
/// the single source of the level symbol, so the right-nav cluster medal
/// ([ClusterLevelMedal]) and the inline level chips (profile cards, analytics
/// headers) all render the same mark instead of a bare `⭐`.
///
/// [level] is drawn per [numberPlacement] when non-null; pass null for a plain
/// level glyph beside its own text label. [height] drives the shield size, and
/// an inside number scales from it. Presentational only — wrap it in an
/// `InkWell` / `Semantics` where it needs to be tappable.
class LevelRibbon extends StatelessWidget {
  final int? level;
  final double height;

  /// Fill for the shield; defaults to the theme's gold. The cluster medal
  /// passes [PangeaColors.goldHighlight] to show hover and the open Level
  /// panel in the mark itself rather than behind it (#8067).
  final Color? color;

  final LevelNumberPlacement numberPlacement;

  /// Style for a [LevelNumberPlacement.trailing] number, so it matches the text
  /// it sits beside. Ignored for an inside number, which scales from [height]
  /// to fit the shield.
  final TextStyle? numberStyle;

  const LevelRibbon({
    required this.height,
    this.level,
    this.color,
    this.numberPlacement = LevelNumberPlacement.inside,
    this.numberStyle,
    super.key,
  });

  /// The [height] at which the shield reads as the same size as a Material
  /// icon drawn at [iconSize] beside it.
  ///
  /// The two do not match at equal nominal sizes: a Material icon insets its
  /// glyph inside its box — `Icons.star` at 16 paints 12.75 of ink — while the
  /// shield path fills its viewBox edge to edge. A shield handed the icon's own
  /// size therefore out-draws it by about a quarter.
  static double heightForIconSize(double iconSize) =>
      iconSize * _materialIconInkRatio;

  /// Measured off a rendered `Icons.star`: 12.75 of ink in a 16 box.
  static const double _materialIconInkRatio = 0.8;

  /// The shield outline from Figma (icon/warning-secondary), in its viewBox
  /// units ([_viewBox]). The one source for both the drawn SVG and
  /// [shieldPath], so a focus ring traced from the path hugs the drawn mark.
  static const _shieldPoints = <Offset>[
    Offset(4.33333, 28.875),
    Offset(4.33333, 17.5656),
    Offset(0, 10.3125),
    Offset(6.16667, 0),
    Offset(18.5, 0),
    Offset(24.6667, 10.3125),
    Offset(20.3333, 17.5656),
    Offset(20.3333, 28.875),
    Offset(12.3333, 26.125),
  ];
  static const _viewBox = Size(24.6667, 28.875);

  static String _shieldSvg(String hexcode) =>
      '<svg viewBox="0 0 ${_viewBox.width} ${_viewBox.height}" '
      'xmlns="http://www.w3.org/2000/svg"><path d="'
      'M${_shieldPoints.map((p) => '${p.dx} ${p.dy}').join('L')}Z" '
      'fill="$hexcode"/></svg>';

  /// The shield's outline scaled into [rect], which should have the shield's
  /// aspect ratio (as a [LevelRibbon]'s own box does).
  static Path shieldPath(Rect rect) => Path()
    ..addPolygon([
      for (final p in _shieldPoints)
        rect.topLeft +
            Offset(
              p.dx * rect.width / _viewBox.width,
              p.dy * rect.height / _viewBox.height,
            ),
    ], true);

  @override
  Widget build(BuildContext context) {
    final width = height * _viewBox.aspectRatio;
    final ribbon = SvgPicture.string(
      _shieldSvg(colorToHex(color ?? Theme.of(context).pangea.goldFixedDim)),
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
    final level = this.level;
    if (level == null) return ribbon;

    // Shield and number announce as one "Level N" whichever side the number is
    // on, so a trailing digit is never read as a loose number (#8918).
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${L10n.of(context).level} $level',
      child: switch (numberPlacement) {
        LevelNumberPlacement.inside => SizedBox(
          width: width,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ribbon,
              // The number sits slightly above the ribbon's notched base.
              Padding(
                padding: EdgeInsets.only(bottom: height * 0.11),
                child: Text(
                  '$level',
                  style: TextStyle(
                    fontSize: height * 0.42,
                    height: 1.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
        LevelNumberPlacement.trailing => Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2.0,
          children: [
            ribbon,
            Text('$level', style: numberStyle),
          ],
        ),
      },
    );
  }
}
