import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';

/// The star field that fills every subscription surface behind its content.
///
/// Held at [SubscriptionConstants.starBackgroundOpacity] because the surfaces
/// place body text directly on it.
class StarBackdrop extends StatelessWidget {
  const StarBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
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
    );
  }
}
