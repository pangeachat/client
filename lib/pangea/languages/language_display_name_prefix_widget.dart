import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:fluffychat/pangea/languages/language_model.dart';

class LanguageDisplayNamePrefixWidget extends StatelessWidget {
  final LanguageModel language;
  final TextStyle style;
  final double iconSize;
  final double spacing;

  const LanguageDisplayNamePrefixWidget(
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
          // Add some spacing between the text and the icon
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: language.isLocalized
                  ? SvgPicture.network(
                      language.svgUrl.toString(),
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      placeholderBuilder: (_) => Center(
                        child: const CircularProgressIndicator(
                          strokeWidth: 0.5,
                        ),
                      ),
                      width: iconSize,
                      height: iconSize,
                    )
                  : Icon(Icons.radio_button_checked, size: iconSize),
            ),
          ),
          WidgetSpan(child: SizedBox(width: spacing)),
          TextSpan(text: language.getDisplayName(context)),
        ],
      ),
    );
  }
}
