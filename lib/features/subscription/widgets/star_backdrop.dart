import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/subscription_constants.dart';
import 'package:fluffychat/features/subscription/widgets/star_field.dart';

/// The star field that fills a subscription surface behind [child].
///
/// Held at [SubscriptionConstants.starBackgroundOpacity] because the surfaces
/// place body text directly on it.
///
/// A surface that draws the two characters itself sets [showCharacters] to
/// false, and the field is cropped to stop above them so they are never
/// painted twice.
class StarBackdrop extends StatelessWidget {
  final Widget child;
  final bool showCharacters;

  const StarBackdrop({
    super.key,
    required this.child,
    this.showCharacters = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: Opacity(
              opacity: SubscriptionConstants.starBackgroundOpacity,
              child: showCharacters
                  ? const StarField()
                  : ClipRect(
                      child: LayoutBuilder(
                        builder: (context, constraints) => OverflowBox(
                          alignment: Alignment.topCenter,
                          maxHeight: double.infinity,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            // Painting the field into a box this much taller
                            // than the surface and then clipping back to the
                            // surface leaves only the part of the art above
                            // the characters on screen.
                            height:
                                constraints.maxHeight /
                                SubscriptionConstants.starCharactersTop,
                            child: const StarField(),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
