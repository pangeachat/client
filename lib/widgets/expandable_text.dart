import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';

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

  @override
  void didUpdateWidget(covariant ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The slot is reused across courses; a new description starts collapsed.
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final linkStyle = style.copyWith(
      color: Theme.of(context).colorScheme.primary,
    );
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    // The toggle is a real control set inline with the text — a Tab stop
    // with a focus ring, announced as a button — where a tap recognizer on a
    // span is reachable by pointer only (#9154).
    WidgetSpan toggle(String label) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      // Its own node: a paragraph merges an inline widget's semantics into
      // its text unless the widget is a boundary, which would announce the
      // whole description as one button.
      child: Semantics(
        container: true,
        child: FocusRingTapTarget(
          onTap: () => setState(() => _expanded = !_expanded),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4.0)),
          ),
          // Outside the glyphs, so the ring never crosses the label.
          ringStrokeAlign: BorderSide.strokeAlignOutside,
          label: label,
          child: Text(label, style: linkStyle),
        ),
      ),
    );

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
                TextSpan(text: '${widget.text} '),
                toggle(l10n.showLess),
              ],
            ),
          );
        }

        // Cut the visible text where the "… Show more" tail still fits on
        // the last collapsed line. Measured as plain text: the inline control
        // draws the same glyphs in the same style, so it takes the same width.
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
              TextSpan(text: '… ', style: linkStyle),
              toggle(l10n.showMore),
            ],
          ),
        );
      },
    );
  }
}
