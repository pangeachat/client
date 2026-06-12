import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/tokens/underline_text_widget.dart';

class GrammarConstructExample extends StatelessWidget {
  final GrammarTag tag;
  final TextStyle? textStyle;
  final TextStyle exampleStyle;
  const GrammarConstructExample({
    super.key,
    required this.tag,
    this.textStyle,
    this.exampleStyle = const TextStyle(fontWeight: FontWeight.w700),
  });

  @override
  Widget build(BuildContext context) {
    final textStyle =
        this.textStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        DefaultTextStyle.of(context).style;
    final exampleStyle = textStyle.merge(this.exampleStyle);

    final List<InlineSpan> children = [];
    final List<String> split = tag.example.split('**');
    for (int i = 0; i < split.length; i++) {
      final text = split[i];
      if (i % 2 == 0) {
        children.add(TextSpan(text: text, style: textStyle));
      } else {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: UnderlineText(
              text: text,
              style: exampleStyle,
              gap: 3,
              underlineColor: exampleStyle.color,
            ),
          ),
        );
      }
    }

    return RichText(text: TextSpan(children: children));
  }
}
