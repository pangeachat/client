import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class ErrorIndicator extends StatelessWidget {
  final String message;
  final double? iconSize;
  final Color? iconColor;
  final TextStyle? style;
  final VoidCallback? onTap;

  const ErrorIndicator({
    super.key,
    required this.message,
    this.iconSize,
    this.iconColor,
    this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final style = defaultStyle.merge(this.style ?? defaultStyle);
    // A live region so screen readers speak the error when this indicator
    // appears (it is shown in place via setState, not as a new route, so it is
    // otherwise silent) — WCAG 4.1.3 (#7203). The decorative error icon carries
    // no semantic label, so only the message is announced.
    final content = Semantics(
      liveRegion: true,
      child: RichText(
        text: TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                Icons.error,
                color: iconColor ?? AppConfig.error,
                size: iconSize ?? 24.0,
              ),
            ),
            TextSpan(text: '  '),
            TextSpan(text: message, style: style),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return TextButton(onPressed: onTap, child: content);
    }

    return content;
  }
}
