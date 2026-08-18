import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';

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
            // A WidgetSpan child is already scaled by the placeholder it
            // sits in; scaling its text here too squares the device text
            // size (#7719).
            child: MediaQuery.withNoTextScaling(
              child: UnderlineText(
                text: text,
                style: exampleStyle,
                gap: 3,
                underlineColor: exampleStyle.color,
              ),
            ),
          ),
        );
      }
    }

    return RichText(
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(children: children),
    );
  }
}
