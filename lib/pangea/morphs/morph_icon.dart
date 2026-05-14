import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/customized_svg.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/utils/color_value.dart';

class MorphIcon extends StatelessWidget {
  const MorphIcon({
    super.key,
    required this.morphFeature,
    required this.morphTag,
    this.size,
  });

  final MorphFeaturesEnum morphFeature;
  final String? morphTag;
  final Size? size;

  String getMorphSvgLink({
    required String morphFeature,
    String? morphTag,
    required BuildContext context,
  }) =>
      "${AppConfig.assetsBaseURL}/${morphFeature.toLowerCase()}_${morphTag?.toLowerCase() ?? ''}.svg";

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return CustomizedSvg(
      svgUrl: getMorphSvgLink(
        morphFeature: morphFeature.name,
        morphTag: morphTag,
        context: context,
      ),
      colorReplacements: theme.brightness == Brightness.dark
          ? {"white": theme.cardColor.hexValue.toString(), "black": "white"}
          : {},
      errorIcon: Icon(morphFeature.fallbackIcon, size: size?.width ?? 24.0),
      width: size?.width,
      height: size?.height,
    );
  }
}
