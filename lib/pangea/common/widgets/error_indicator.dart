import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/rate_limit_pause.dart';

/// [fallback] unless [error] is the backend throttling us (429, or a read a
/// [RateLimitPause] suppressed), which shows the shared "wait a moment and
/// try again" copy instead — the surface's own copy tends to blame the wrong
/// thing ("check your connection") when the real remedy is waiting (#8705).
String rateLimitAwareCopy(
  BuildContext context,
  Object? error,
  String fallback,
) => RateLimitPause.isRateLimited(error)
    ? L10n.of(context).errorRateLimited
    : fallback;

class ErrorIndicator extends StatelessWidget {
  final String message;

  /// The failure behind this indicator, when the caller has it — a throttle
  /// replaces [message] per [rateLimitAwareCopy].
  final Object? error;

  final double? iconSize;
  final Color? iconColor;
  final TextStyle? style;
  final VoidCallback? onTap;

  const ErrorIndicator({
    super.key,
    required this.message,
    this.error,
    this.iconSize,
    this.iconColor,
    this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final message = rateLimitAwareCopy(context, error, this.message);
    final defaultStyle = DefaultTextStyle.of(context).style;
    final style = defaultStyle.merge(this.style ?? defaultStyle);
    // A live region so screen readers speak the error when this indicator
    // appears (it is shown in place via setState, not as a new route, so it is
    // otherwise silent) — WCAG 4.1.3 (#7203). The decorative error icon carries
    // no semantic label, so only the message is announced.
    final content = Semantics(
      liveRegion: true,
      child: RichText(
        textScaler: MediaQuery.textScalerOf(context),
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
