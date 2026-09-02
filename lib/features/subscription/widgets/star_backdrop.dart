import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';

/// The star field that fills a subscription surface behind [child].
///
/// Held at [SubscriptionConstants.starBackgroundOpacity] because the surfaces
/// place body text directly on it.
///
/// When [reserveStarBand] is set, [child] is confined to the top of the body
/// so it can never cover the star carrying the two characters. See
/// [SubscriptionConstants.starBandFraction].
class StarBackdrop extends StatelessWidget {
  final Widget child;
  final bool reserveStarBand;

  const StarBackdrop({
    super.key,
    required this.child,
    this.reserveStarBand = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox.expand(
          child: ExcludeSemantics(
            child: Opacity(
              opacity: SubscriptionConstants.starBackgroundOpacity,
              child: CachedNetworkImage(
                imageUrl:
                    "${AppConfig.assetsBaseURL}/${SubscriptionConstants.starBackground}",
                fit: BoxFit.cover,
                alignment: Alignment.center,
                placeholder: (context, url) => const SizedBox(),
                errorWidget: (context, url, error) => const SizedBox(),
              ),
            ),
          ),
        ),
        if (!reserveStarBand)
          child
        else
          LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                Expanded(child: child),
                SizedBox(
                  height:
                      constraints.maxHeight *
                      SubscriptionConstants.starBandFraction,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
