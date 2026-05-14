import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';

class MorphTagDisplay extends StatelessWidget {
  final String feature;
  final String tag;
  final Color textColor;

  const MorphTagDisplay({
    super.key,
    required this.feature,
    required this.tag,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 32.0,
          height: 32.0,
          child: MorphIcon(feature: feature, tag: tag),
        ),
        const SizedBox(width: 10.0),
        Text(
          GrammarConstructsProvider.getTagTitle(feature: feature, tag: tag) ??
              tag,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: textColor),
        ),
      ],
    );
  }
}
