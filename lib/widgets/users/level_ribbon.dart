import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

import 'package:fluffychat/config/app_config.dart';

/// The gold ribbon/shield that represents a learner's level across the app —
/// the single source of the level symbol, so the right-nav cluster medal
/// ([ClusterLevelMedal]) and the inline level chips (profile cards, analytics
/// headers) all render the same mark instead of a bare `⭐`.
///
/// [level] is overlaid on the shield when non-null; pass null for a plain
/// level glyph beside its own text label. [height] drives the shield size and
/// the number scales from it. Presentational only — wrap it in an `InkWell` /
/// `Semantics` where it needs to be tappable.
class LevelRibbon extends StatelessWidget {
  final int? level;
  final double height;

  const LevelRibbon({required this.height, this.level, super.key});

  /// The shield outline from Figma (icon/warning-secondary), filled [hexcode].
  static String _shieldSvg(String hexcode) =>
      '<svg viewBox="0 0 24.6667 28.875" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4.33333 28.875V17.5656L0 10.3125L6.16667 0H18.5L24.6667 '
      '10.3125L20.3333 17.5656V28.875L12.3333 26.125L4.33333 28.875Z" '
      'fill="$hexcode"/></svg>';

  @override
  Widget build(BuildContext context) {
    // Shield aspect ratio from the viewBox (24.6667 x 28.875).
    final width = height * (24.6667 / 28.875);
    final ribbon = SvgPicture.string(
      _shieldSvg(AppConfig.goldHexByTheme(context)),
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
    final level = this.level;
    if (level == null) return ribbon;

    return SizedBox(
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
    );
  }
}
