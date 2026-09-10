import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

import 'package:fluffychat/config/app_config.dart';
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
  /// passes [AppConfig.goldHighlightByTheme] to show hover and the open Level
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
      _shieldSvg(colorToHex(color ?? AppConfig.goldByTheme(context))),
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
