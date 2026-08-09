import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/customized_svg.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/utils/color_value.dart';

class MorphIcon extends StatelessWidget {
  final MorphFeaturesEnum feature;
  final String? tag;
  final Size? size;

  const MorphIcon({super.key, required this.feature, this.tag, this.size});

  String getMorphSvgLink({required BuildContext context}) =>
      "${AppConfig.assetsBaseURL}/${feature.name.toLowerCase()}_${tag?.toLowerCase() ?? ''}.svg";

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return CustomizedSvg(
      svgUrl: getMorphSvgLink(context: context),
      colorReplacements: theme.brightness == Brightness.dark
          ? {"white": theme.cardColor.hexValue.toString(), "black": "white"}
          : {},
      errorIcon: Icon(feature.fallbackIcon, size: size?.width ?? 24.0),
      width: size?.width,
      height: size?.height,
    );
  }
}
