import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class TokenRenderingUtil {
  final TextStyle existingStyle;

  TokenRenderingUtil({
    required this.existingStyle,
  });

  static final Map<String, double> _tokensWidthCache = {};

  TextStyle style({
    required Color underlineColor,
    double? fontSize,
    bool selected = false,
    bool highlighted = false,
    bool isNew = false,
    bool practiceMode = false,
    bool hovered = false,
  }) =>
      existingStyle.copyWith(
        fontSize: fontSize,
        decoration: TextDecoration.underline,
        decorationThickness: 4,
        decorationColor: _underlineColor(
          underlineColor,
          selected: selected,
          highlighted: highlighted,
          isNew: isNew,
          practiceMode: practiceMode,
          hovered: hovered,
        ),
      );

  double tokenTextWidthForContainer(
    String text,
    Color underlineColor, {
    double? fontSize,
  }) {
    final tokenSizeKey = "$text-$fontSize";
    if (_tokensWidthCache.containsKey(tokenSizeKey)) {
      return _tokensWidthCache[tokenSizeKey]!;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: style(
          underlineColor: underlineColor,
          fontSize: fontSize,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = textPainter.width;
    textPainter.dispose();

    _tokensWidthCache[tokenSizeKey] = width;
    return width;
  }

  Color _underlineColor(
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
