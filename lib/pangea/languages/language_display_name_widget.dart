import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:fluffychat/pangea/languages/language_model.dart';

class LanguageDisplayNameWidget extends StatelessWidget {
  final LanguageModel language;
  final TextStyle style;
  final double iconSize;
  final double spacing;

  const LanguageDisplayNameWidget(
    this.language, {
    super.key,
    required this.style,
    required this.iconSize,
    this.spacing = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: language.getDisplayName(context)),
          if (language.isLocalized) ...[
            WidgetSpan(
              child: SizedBox(width: spacing),
            ), // Add some spacing between the text and the icon
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox(
                width: iconSize,
                height: iconSize,
                child: SvgPicture.network(
                  language.svgUrl.toString(),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  placeholderBuilder: (_) => Center(
                    child: const CircularProgressIndicator(strokeWidth: 0.5),
                  ),
                  width: iconSize,
                  height: iconSize,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
