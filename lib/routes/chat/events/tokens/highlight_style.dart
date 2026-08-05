import 'package:flutter/material.dart';

import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';

/// A color-parameterized inline highlight [TextStyle]: UNDERLINE ([color] at a
/// shared token decoration thickness when [fill] is false, or BACKFILL
/// ([color] as the background) when [fill] is true.
///
/// Extracted VERBATIM from the private `PangeaTextController._underlineStyle`
/// (`pangea_text_controller.dart`) so the IGC input field and the streaming
/// edit-diff view share one primitive. Behaviour-identical mapping:
/// `_underlineStyle(c, isSelected)` == `highlightTextStyle(color: c, fill: isSelected)`.
TextStyle highlightTextStyle({required Color color, bool fill = false}) =>
    TextStyle(
      decoration: fill ? null : TextDecoration.underline,
      decorationColor: fill ? null : color,
      decorationThickness: fill ? null : tokenUnderlineHeight,
      backgroundColor: fill ? color : null,
    );

/// The rounded backfill box behind `TokenRenderingUtil.vocabHighlight`, now
/// color-parameterized (was gold-hardcoded): [color] drawn at alpha 50 with a
/// 12px radius and 4px horizontal padding around [child].
Widget highlightBox({required Color color, required Widget child}) =>
    DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      ),
    );
