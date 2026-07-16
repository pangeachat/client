import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class TokenRenderingUtil {
  TokenRenderingUtil();

  static final Map<String, double> _tokensWidthCache = {};

  double tokenTextWidthForContainer(
    String text,
    Color underlineColor,
    TextStyle style,
    double fontSize,
  ) {
    final tokenSizeKey = "$text-$fontSize";
    if (_tokensWidthCache.containsKey(tokenSizeKey)) {
      return _tokensWidthCache[tokenSizeKey]!;
    }

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = textPainter.width;
    textPainter.dispose();

    _tokensWidthCache[tokenSizeKey] = width;
    return width;
  }

  static Color underlineColor(
    Color underlineColor, {
    bool selected = false,
    bool highlighted = false,
    bool isNew = false,
    bool practiceMode = false,
    bool hovered = false,
  }) {
    if (practiceMode) return Colors.white.withAlpha(0);
    if (highlighted) return underlineColor;
    if (isNew) return AppConfig.success.withAlpha(200);
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

  /// Wraps [child] in the gold target-vocab highlight when [highlight] is
  /// true, otherwise returns [child] unchanged. Keeps the typed and spoken
  /// highlights visually identical.
  static Widget vocabHighlight({
    required bool highlight,
    required Widget child,
  }) {
    if (!highlight) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppConfig.gold.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      ),
    );
  }
}
