import 'package:flutter/material.dart';

import 'package:fluffychat/features/languages/language_flag_or_fallback.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/widgets/network_svg.dart';

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
///
/// [tintColor] overrides the ring/background color (default
/// `colorScheme.primary`) — the context language chips use this to signal a
/// mismatch with the learner's target language (profile.instructions.md,
/// "Switching from context").
class LanguageFlagChip extends StatelessWidget {
  final LanguageModel? language;
  final String langCode;
  final double width;
  final double height;
  final double fontSize;
  final double radius;
  final double borderWidth;
  final bool alwaysShowCode;
  final Color? tintColor;

  const LanguageFlagChip({
    required this.language,
    required this.langCode,
    this.width = 52.0,
    this.height = 36.0,
    this.fontSize = 18.0,
    this.radius = 6.0,
    this.borderWidth = 2.0,
    this.alwaysShowCode = true,
    this.tintColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = this.language;
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

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(borderWidth),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tintColor ?? theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(radius + borderWidth),
      ),
      child: language == null
          ? outlinedText
          : LanguageFlagOrFallback(
              language: language,
              flag: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  children: [
                    NetworkSvg(
                      svgUrl: language.svgUrl.toString(),
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                      // Markup that arrived but won't parse. The code is
                      // already drawn over it when [alwaysShowCode], and a
                      // second copy of it lands off-centre (#8548).
                      errorWidget: alwaysShowCode
                          ? const SizedBox.shrink()
                          : Center(child: outlinedText),
                      placeholder: SizedBox(width: width, height: height),
                    ),
                    if (alwaysShowCode)
                      Positioned(child: Center(child: outlinedText)),
                  ],
                ),
              ),
              fallback: outlinedText,
            ),
    );
  }
}
