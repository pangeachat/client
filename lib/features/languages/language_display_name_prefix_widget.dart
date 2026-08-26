import 'package:flutter/material.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/network_svg.dart';

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
              ? NetworkSvg(
                  svgUrl: language.svgUrl.toString(),
                  width: iconSize,
                  height: iconSize,
                  placeholder: const Center(
                    child: CircularProgressIndicator(strokeWidth: 0.5),
                  ),
                )
              : Icon(Icons.language, size: iconSize),
        ),
        SizedBox(height: spacing),
        Text(
          language.getDisplayName(L10n.of(context)),
          style: style,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
