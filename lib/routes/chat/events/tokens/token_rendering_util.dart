import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/routes/chat/events/tokens/highlight_style.dart';

class TokenRenderingUtil {
  TokenRenderingUtil();

  static final Map<String, double> _tokensWidthCache = {};

  /// [textScaler] must be the device scaler the token is actually rendered
  /// with — a width measured at one scale and rendered at another leaves the
  /// underline and highlight box off the word. It is part of the cache key for
  /// the same reason: the cached width is only valid at the scale it was
  /// measured at.
  double tokenTextWidthForContainer(
    String text,
    Color underlineColor,
    TextStyle style,
    double fontSize,
    TextScaler textScaler,
  ) {
    final tokenSizeKey = "$text-$fontSize-${textScaler.scale(fontSize)}";
    if (_tokensWidthCache.containsKey(tokenSizeKey)) {
      return _tokensWidthCache[tokenSizeKey]!;
    }

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final width = textPainter.width;
    textPainter.dispose();

    _tokensWidthCache[tokenSizeKey] = width;
    return width;
  }

  static Color underlineColor(
    BuildContext context,
    Color underlineColor, {
    bool selected = false,
    bool highlighted = false,
    bool isNew = false,
    bool practiceMode = false,
    bool hovered = false,
  }) {
    if (practiceMode) return Colors.white.withAlpha(0);
    if (highlighted) return underlineColor;
    // A new word's underline is the success mark, drawn nearly opaque.
    if (isNew) return Theme.of(context).pangea.successGraphic.withAlpha(200);
    if (selected) return underlineColor;
    if (hovered) return underlineColor.withAlpha(100);
    return Colors.white.withAlpha(0);
  }

  /// Whether a token whose lemma is [lemmaText] is one of the activity's
  /// target vocab words. [vocabLemmas] must already be lower-cased; pass
  /// null when the room has no activity plan. Shared by the typed-message
  /// renderer and the STT transcript renderer so spoken and typed target
  /// vocab highlight identically (issue #7659).
  static bool isVocabHighlight(String lemmaText, Set<String>? vocabLemmas) =>
      vocabLemmas != null && vocabLemmas.contains(lemmaText.toLowerCase());

  /// Wraps [child] in the target-vocab backfill highlight when [highlight] is
  /// true, otherwise returns [child] unchanged. [color] defaults to the theme's
  /// bright gold, the vocab tint (issue #7659), resolved where the box renders;
  /// the STT edit-diff passes [PangeaColors.warningGraphic]. Keeps the typed
  /// and spoken highlights visually identical.
  static Widget vocabHighlight({
    required bool highlight,
    required Widget child,
    Color? color,
  }) {
    if (!highlight) return child;
    if (color != null) return highlightBox(color: color, child: child);
    return Builder(
      builder: (context) => highlightBox(
        color: Theme.of(context).pangea.goldFixedDim,
        child: child,
      ),
    );
  }
}
