import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:fluffychat/utils/url_launcher.dart';

const double tokenUnderlineHeight = 3;
const double tokenUnderlineGap = 2;

/// A dash's length as a multiple of the rule's thickness. Long enough to read
/// as a dashed line rather than a dotted one at the 3px token thickness.
const double _dashLengthRatio = 2;

class UnderlineText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;
  final TextDirection? textDirection;
  final Color? underlineColor;
  final double underlineHeight;
  final double gap;

  /// Draw the rule as dashes rather than one continuous bar, so two underlines
  /// can be told apart without relying on their colours (SC 1.4.1). The STT
  /// transcript diff dashes its unchanged words; see [sttUnchangedUnderlineStyle],
  /// which is the same distinction on the [TextDecoration] rendering path.
  final bool dashed;

  const UnderlineText({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
    this.textDirection,
    this.underlineColor,
    this.underlineHeight = tokenUnderlineHeight,
    this.gap = tokenUnderlineGap,
    this.dashed = false,
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

    // RichText and TextPainter both default to TextScaler.noScaling, so the
    // device text size reaches neither unless it is passed explicitly. The
    // underline is painted from a separate layout of the same span, so the
    // two must be given the same scaler or every underline lands off its word.
    final textScaler = MediaQuery.textScalerOf(context);

    final richText = RichText(
      textDirection: textDirection,
      text: span,
      textScaler: textScaler,
    );
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
        textScaler: textScaler,
        dashed: dashed,
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
  final TextScaler textScaler;
  final bool dashed;

  _UnderlinePainter({
    required this.span,
    required this.textDirection,
    required this.underlineColor,
    required this.underlineHeight,
    required this.gap,
    required this.textScaler,
    required this.dashed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: span,
      textDirection: textDirection,
      textScaler: textScaler,
    );

    textPainter.layout(maxWidth: size.width);

    final paint = Paint()
      ..color = underlineColor
      ..style = PaintingStyle.fill;

    final lines = textPainter.computeLineMetrics();
    textPainter.dispose();

    for (final line in lines) {
      final y = line.baseline + gap;

      if (!dashed) {
        canvas.drawRect(
          Rect.fromLTWH(line.left, y, line.width, underlineHeight),
          paint,
        );
        continue;
      }
      // Dashes rather than one bar, so this underline reads as a different
      // mark from a solid one with colour removed (SC 1.4.1, #8764). The last
      // dash is clipped to the word's end rather than overhanging it.
      final period = underlineHeight * _dashLengthRatio + underlineHeight;
      final end = line.left + line.width;
      for (var x = line.left; x < end; x += period) {
        final width = math.min(underlineHeight * _dashLengthRatio, end - x);
        canvas.drawRect(Rect.fromLTWH(x, y, width, underlineHeight), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UnderlinePainter oldDelegate) {
    return oldDelegate.span != span ||
        oldDelegate.underlineColor != underlineColor ||
        oldDelegate.gap != gap ||
        oldDelegate.underlineHeight != underlineHeight ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.dashed != dashed;
  }
}
