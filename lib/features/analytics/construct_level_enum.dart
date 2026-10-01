import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/analytics/analytics_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/customized_svg.dart';

enum ConstructLevelEnum {
  flowers,
  greens,
  seeds;

  /// The stage's colour as text or a mark on the surface: the theme's text
  /// tone of the brand purple, the success green or the gold, so it clears
  /// 4.5:1 in both themes. Washes take it at a low alpha.
  Color color(BuildContext context) {
    final theme = Theme.of(context);
    switch (this) {
      case ConstructLevelEnum.flowers:
        return theme.colorScheme.primary;
      case ConstructLevelEnum.greens:
        return theme.pangea.success;
      case ConstructLevelEnum.seeds:
        return theme.pangea.gold;
    }
  }

  String get _svgURL {
    switch (this) {
      case ConstructLevelEnum.seeds:
        return "${AppConfig.assetsBaseURL}/${AnalyticsConstants.seedSvgFileName}";
      case ConstructLevelEnum.greens:
        return "${AppConfig.assetsBaseURL}/${AnalyticsConstants.leafSvgFileName}";
      case ConstructLevelEnum.flowers:
        return "${AppConfig.assetsBaseURL}/${AnalyticsConstants.flowerSvgFileName}";
    }
  }

  /// The stage's user-facing name — what a screen reader says wherever the
  /// visual is the stage icon alone (the vocab filter chips, the word tiles).
  /// The seeds→greens→flowers metaphor per analytics-system.instructions.md.
  String displayName(L10n l10n) {
    switch (this) {
      case ConstructLevelEnum.flowers:
        return l10n.constructLevelFlowers;
      case ConstructLevelEnum.greens:
        return l10n.constructLevelGreens;
      case ConstructLevelEnum.seeds:
        return l10n.constructLevelSeeds;
    }
  }

  String get emoji {
    switch (this) {
      case ConstructLevelEnum.flowers:
        return AnalyticsConstants.emojiForFlower;
      case ConstructLevelEnum.greens:
        return AnalyticsConstants.emojiForGreen;
      case ConstructLevelEnum.seeds:
        return AnalyticsConstants.emojiForSeed;
    }
  }

  String get xpString {
    switch (this) {
      case ConstructLevelEnum.flowers:
        return ">${AnalyticsConstants.xpForFlower}";
      case ConstructLevelEnum.greens:
        return ">${AnalyticsConstants.xpForGreens}";
      case ConstructLevelEnum.seeds:
        return "<${AnalyticsConstants.xpForGreens}";
    }
  }

  int get xpNeeded {
    switch (this) {
      case ConstructLevelEnum.flowers:
        return AnalyticsConstants.xpForFlower;
      case ConstructLevelEnum.greens:
        return AnalyticsConstants.xpForGreens;
      case ConstructLevelEnum.seeds:
        return 0;
    }
  }

  Widget icon([double? size]) => CustomizedSvg(
    svgUrl: _svgURL,
    colorReplacements: const {},
    errorIcon: Text(emoji, style: TextStyle(fontSize: size ?? 24)),
    width: size,
    height: size,
  );
}
