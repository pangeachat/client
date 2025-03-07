import 'package:fluffychat/pangea/common/widgets/customized_svg.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:flutter/material.dart';

class ConstructLevelIcon extends StatelessWidget {
  const ConstructLevelIcon({
    super.key,
    required this.constructLemmaCategory,
  });

  final ConstructLevelEnum? constructLemmaCategory;

  @override
  Widget build(BuildContext context) {
    return CustomizedSvg(
      svgUrl: constructLemmaCategory?.svgURL ?? ConstructLevelEnum.seeds.svgURL,
      colorReplacements: const {},
      errorIcon: Text(
        constructLemmaCategory?.emoji ?? ConstructLevelEnum.seeds.svgURL,
        style: const TextStyle(
          fontSize: 20,
        ),
      ),
    );
  }
}
