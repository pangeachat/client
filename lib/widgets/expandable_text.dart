import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// Text collapsed to [maxLines] with an inline "Show more" tail when it
/// overflows, expanding in place to the full text with an inline "Show less".
/// Text that fits renders plainly, with no toggle at all.
class ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;

  const ExpandableText(this.text, {this.style, this.maxLines = 2, super.key});

  @override
  State<ExpandableText> createState() => ExpandableTextState();
}

class ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  late final TapGestureRecognizer _toggleRecognizer = TapGestureRecognizer()
    ..onTap = () => setState(() => _expanded = !_expanded);

  @override
  void didUpdateWidget(covariant ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The slot is reused across courses; a new description starts collapsed.
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  void dispose() {
    _toggleRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final linkStyle = style.copyWith(
      color: Theme.of(context).colorScheme.primary,
    );
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final fullPainter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.maxLines,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: maxWidth);
        final overflows = fullPainter.didExceedMaxLines;
        fullPainter.dispose();

        if (!overflows) {
          return Text(widget.text, style: style);
        }

        final l10n = L10n.of(context);
        if (_expanded) {
          return Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(text: widget.text),
                TextSpan(
                  text: ' ${l10n.showLess}',
                  style: linkStyle,
                  recognizer: _toggleRecognizer,
                ),
              ],
            ),
          );
        }

        // Cut the visible text where the "… Show more" tail still fits on
        // the last collapsed line.
        final tailText = '… ${l10n.showMore}';
        final tailPainter = TextPainter(
          text: TextSpan(text: tailText, style: linkStyle),
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: maxWidth);
        final collapsedPainter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.maxLines,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: maxWidth);
        final cutoff = collapsedPainter.getPositionForOffset(
          Offset(
            math.max(maxWidth - tailPainter.width, 0),
            collapsedPainter.height - 1,
          ),
        );
        tailPainter.dispose();
        collapsedPainter.dispose();

        final visible = widget.text
            .substring(0, math.max(cutoff.offset, 0))
            .trimRight();
        return Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(text: visible),
              TextSpan(
                text: tailText,
                style: linkStyle,
                recognizer: _toggleRecognizer,
              ),
            ],
          ),
        );
      },
    );
  }
}
