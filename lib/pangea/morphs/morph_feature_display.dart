import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';

class MorphFeatureDisplay extends StatelessWidget {
  final GrammarFeature feature;
  const MorphFeatureDisplay({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 24.0,
          height: 24.0,
          child: MorphIcon(feature: feature.value),
        ),
        const SizedBox(width: 10.0),
        Text(feature.title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
