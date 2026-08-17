import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:fluffychat/utils/url_launcher.dart';

const double tokenUnderlineHeight = 3;
const double tokenUnderlineGap = 2;

class UnderlineText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;
  final TextDirection? textDirection;
  final Color? underlineColor;
  final double underlineHeight;
  final double gap;

  const UnderlineText({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
    this.textDirection,
    this.underlineColor,
    this.underlineHeight = tokenUnderlineHeight,
    this.gap = tokenUnderlineGap,
  });

  @override
  Widget build(BuildContext context) {
    final span = TextSpan(
      children: [
        LinkifySpan(
          text: text,
          style: style,
          linkStyle: linkStyle,
          onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
        ),
      ],
    );

    final richText = RichText(textDirection: textDirection, text: span);
    final color = underlineColor ?? Colors.transparent;

    // A fully transparent underline draws nothing — the common case for
    // ordinary tokens. Skip the CustomPaint and the second text layout its
    // painter runs (issue #8426).
    if (color.a == 0) return richText;

    return CustomPaint(
      painter: _UnderlinePainter(
        span: span,
        textDirection: textDirection ?? TextDirection.ltr,
        underlineColor: color,
        underlineHeight: underlineHeight,
        gap: gap,
      ),
      child: richText,
    );
  }
}

class _UnderlinePainter extends CustomPainter {
  final TextSpan span;
  final TextDirection textDirection;
  final Color underlineColor;
  final double underlineHeight;
  final double gap;

  _UnderlinePainter({
    required this.span,
    required this.textDirection,
    required this.underlineColor,
    required this.underlineHeight,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(text: span, textDirection: textDirection);

    textPainter.layout(maxWidth: size.width);

    final paint = Paint()
      ..color = underlineColor
      ..style = PaintingStyle.fill;

    final lines = textPainter.computeLineMetrics();
    textPainter.dispose();

    for (final line in lines) {
      final y = line.baseline + gap;

      canvas.drawRect(
        Rect.fromLTWH(line.left, y, line.width, underlineHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UnderlinePainter oldDelegate) {
    return oldDelegate.span != span ||
        oldDelegate.underlineColor != underlineColor ||
        oldDelegate.gap != gap ||
        oldDelegate.underlineHeight != underlineHeight;
  }
}
