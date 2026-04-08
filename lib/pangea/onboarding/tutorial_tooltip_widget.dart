import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';

class TutorialTooltipWidget extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final TextStyle? textStyle;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const TutorialTooltipWidget({
    required this.text,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.textStyle,
    this.iconSize = 32.0,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final background = backgroundColor ?? theme.colorScheme.onSurface;
    final foreground = foregroundColor ?? theme.colorScheme.surface;

    final style =
        textStyle ?? theme.textTheme.bodyMedium?.copyWith(color: foreground);

    return Container(
      padding: padding,
      decoration: BoxDecoration(color: background, borderRadius: borderRadius),
      child: Row(
        spacing: 8.0,
        children: [
          BotFace(width: iconSize, expression: BotExpression.gold),
          Expanded(
            child: Text(text, style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
