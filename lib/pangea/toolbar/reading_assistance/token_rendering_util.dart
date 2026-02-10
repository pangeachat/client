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
}
