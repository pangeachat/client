import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';

class GrammarConstructExample extends StatelessWidget {
  final GrammarTag tag;
  final TextStyle? textStyle;
  final TextStyle exampleStyle;
  const GrammarConstructExample({
    super.key,
    required this.tag,
    this.textStyle,
    this.exampleStyle = const TextStyle(
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationThickness: 2.0,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = this.textStyle ?? Theme.of(context).textTheme.bodyLarge;
    final exampleStyle = textStyle?.merge(this.exampleStyle);

    final List<TextSpan> children = [];
    final List<String> split = tag.example.split('**');
    for (int i = 0; i < split.length; i++) {
      final text = split[i];
      children.add(
        TextSpan(text: text, style: i % 2 == 0 ? textStyle : exampleStyle),
      );
    }

    return RichText(text: TextSpan(children: children));
  }
}
