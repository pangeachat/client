import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';

class MorphTagDisplay extends StatelessWidget {
  const MorphTagDisplay({
    super.key,
    required MorphFeaturesEnum morphFeature,
    required String morphTag,
    required this.textColor,
  }) : _morphFeature = morphFeature,
       _morphTag = morphTag;

  final MorphFeaturesEnum _morphFeature;
  final String _morphTag;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 32.0,
          height: 32.0,
          child: MorphIcon(morphFeature: _morphFeature, morphTag: _morphTag),
        ),
        const SizedBox(width: 10.0),
        Text(
          GrammarConstructsProvider.getTagTitle(
                feature: _morphFeature.name,
                tag: _morphTag,
              ) ??
              _morphTag,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: textColor),
        ),
      ],
    );
  }
}
