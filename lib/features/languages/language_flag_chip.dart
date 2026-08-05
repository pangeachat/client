import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:fluffychat/features/languages/language_model.dart';

/// The primary-tinted language chip shared by the analytics cluster's
/// `ClusterLanguageFlag` and the activity start page's info row. It never
/// renders empty: the target language's flag when there is one, otherwise the
/// uppercase language code on the primary container — and a null [language]
/// (an unresolved code) still shows the [langCode] chip. If the flag SVG fails
/// to load it falls back to the code too.
///
/// [alwaysShowCode] overlays the code on the flag as well (the cluster's
/// identity treatment); left false the flag shows alone, with the code only as
/// the no-flag fallback (the info row, where an overlay would crowd the small
/// chip). Passive — callers needing a tap/tooltip wrap it. See
/// activity-start-page.instructions.md.
class LanguageFlagChip extends StatelessWidget {
  final LanguageModel? language;
  final String langCode;
  final double width;
  final double height;
  final double fontSize;
  final double radius;
  final double borderWidth;
  final bool alwaysShowCode;

  const LanguageFlagChip({
    required this.language,
    required this.langCode,
    this.width = 52.0,
    this.height = 36.0,
    this.fontSize = 18.0,
    this.radius = 6.0,
    this.borderWidth = 2.0,
    this.alwaysShowCode = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = (language?.langCodeShort ?? langCode).toUpperCase();
    // Stroke scales with the font so the outline reads the same at any size
    // (4px at the cluster's 18pt).
    final outlinedText = Stack(
      children: <Widget>[
        Text(
          code,
          style: TextStyle(
            fontSize: fontSize,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = fontSize / 4.5
              ..color = Colors.white,
          ),
        ),
        Text(
          code,
          style: TextStyle(fontSize: fontSize, color: Colors.black),
        ),
      ],
    );

    final showFlag = language?.shouldShowFlag ?? false;

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(borderWidth),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(radius + borderWidth),
      ),
      child: showFlag
          ? ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                children: [
                  SvgPicture.network(
                    language!.svgUrl.toString(),
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => outlinedText,
                    placeholderBuilder: (_) =>
                        SizedBox(width: width, height: height),
                  ),
                  if (alwaysShowCode)
                    Positioned(child: Center(child: outlinedText)),
                ],
              ),
            )
          : outlinedText,
    );
  }
}
