import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/customized_svg.dart';
import 'package:fluffychat/pangea/morphs/get_grammar_copy.dart';
import 'package:fluffychat/pangea/morphs/get_icon_for_morph_feature.dart';
import 'package:fluffychat/pangea/morphs/get_svg_link.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/utils/color_value.dart';

class MorphIcon extends StatelessWidget {
  const MorphIcon({
    super.key,
    required this.morphFeature,
    required this.morphTag,
    this.showTooltip = false,
  });

  final String morphFeature;
  final String? morphTag;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    // debugPrint("MorphIcon: morphFeature: $morphFeature, morphTag: $morphTag");

    final ThemeData theme = Theme.of(context);

    return Tooltip(
      message: morphTag == null
          ? getMorphologicalCategoryCopy(
              morphFeature,
              context,
            )
          : getGrammarCopy(
              category: morphFeature,
              lemma: morphTag!,
              context: context,
            ),
      triggerMode: TooltipTriggerMode.tap,
      child: CustomizedSvg(
        svgUrl: getMorphSvgLink(
          morphFeature: morphFeature,
          morphTag: morphTag,
          context: context,
        ),
        colorReplacements: theme.brightness == Brightness.dark
            ? {
                "white": theme.cardColor.hexValue.toString(),
                "black": "white",
              }
            : {},
        errorIcon: Icon(getIconForMorphFeature(morphFeature)),
      ),
    );
  }
}
