import 'package:flutter/material.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/network_svg.dart';

class LanguageDisplayNamePostfixWidget extends StatelessWidget {
  final LanguageModel language;
  final TextStyle style;
  final double iconSize;
  final double spacing;

  const LanguageDisplayNamePostfixWidget(
    this.language, {
    super.key,
    required this.style,
    required this.iconSize,
    this.spacing = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: language.getDisplayName(L10n.of(context))),
          if (language.shouldShowFlag) ...[
            WidgetSpan(
              child: SizedBox(width: spacing),
            ), // Add some spacing between the text and the icon
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox(
                width: iconSize,
                height: iconSize,
                child: NetworkSvg(
                  svgUrl: language.svgUrl.toString(),
                  placeholder: const Center(
                    child: CircularProgressIndicator(strokeWidth: 0.5),
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
