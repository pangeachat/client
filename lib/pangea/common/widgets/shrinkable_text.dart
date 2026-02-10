import 'package:flutter/material.dart';

class ShrinkableText extends StatelessWidget {
  final String text;
  final double maxWidth;
  final TextStyle? style;
  final Alignment? alignment;

  const ShrinkableText({
    super.key,
    required this.text,
    required this.maxWidth,
    this.alignment,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          alignment: alignment,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(text, style: style),
          ),
        );
      },
    );
  }
}
