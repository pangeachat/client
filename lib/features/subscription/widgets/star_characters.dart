import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/star_field.dart';

/// The star carrying the two characters, cut out of the star art and drawn at
/// a size of its own.
///
/// The surfaces place this in their scroll content rather than leaving it to
/// the ambient field, where the viewport decides where it lands and the
/// content covers it (#8751).
class StarCharacters extends StatelessWidget {
  final double width;

  const StarCharacters({
    super.key,
    this.width = SubscriptionConstants.starCharactersDisplayWidth,
  });

  @override
  Widget build(BuildContext context) {
    const cropWidth = SubscriptionConstants.starCharactersWidth;
    const cropHeight = SubscriptionConstants.starCharactersHeight;

    // The whole art, scaled so that the characters' slice of it comes out at
    // [width]. Only that slice is shown; the rest is clipped away.
    final fieldWidth = width / cropWidth;
    final fieldHeight = fieldWidth / SubscriptionConstants.starBackgroundAspect;

    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: fieldHeight * cropHeight,
        child: ClipRect(
          child: OverflowBox(
            // Offsetting the oversized art within this box is what brings the
            // characters into view and leaves everything else outside it.
            alignment: Alignment(
              2 * SubscriptionConstants.starCharactersLeft / (1 - cropWidth) -
                  1,
              2 * SubscriptionConstants.starCharactersTop / (1 - cropHeight) -
                  1,
            ),
            minWidth: fieldWidth,
            maxWidth: fieldWidth,
            minHeight: fieldHeight,
            maxHeight: fieldHeight,
            child: const StarField(),
          ),
        ),
      ),
    );
  }
}
