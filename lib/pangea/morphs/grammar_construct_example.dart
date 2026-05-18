import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';

class GrammarConstructExample extends StatelessWidget {
  final GrammarTag tag;
  final TextStyle? style;
  const GrammarConstructExample({super.key, required this.tag, this.style});

  @override
  Widget build(BuildContext context) {
    final textStyle = style ?? Theme.of(context).textTheme.bodyLarge;

    final List<TextSpan> children = [];
    final List<String> split = tag.example.split('**');
    for (int i = 0; i < split.length; i++) {
      if (i % 2 == 0) {
        children.add(TextSpan(text: split[i], style: textStyle));
      } else {
        children.add(
          TextSpan(
            text: split[i],
            style: textStyle!.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      }
    }

    return RichText(text: TextSpan(children: children));
  }
}
