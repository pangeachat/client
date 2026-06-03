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
    this.spacing = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: iconSize,
          height: iconSize,
          child: language.shouldShowFlag
              ? SvgPicture.network(
                  language.svgUrl.toString(),
                  width: iconSize,
                  height: iconSize,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  placeholderBuilder: (_) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 0.5),
                  ),
                )
              : Icon(Icons.language, size: iconSize),
        ),
        SizedBox(height: spacing),
        Text(
          language.getDisplayName(context),
          style: style,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
