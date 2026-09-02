import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/subscription/subscription_constants.dart';

/// The subscription star art, painted to cover whatever box it is given.
///
/// Both the ambient field behind a surface and the placed characters are cut
/// from this one asset, so the two always come from the same file.
class StarField extends StatelessWidget {
  const StarField({super.key});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl:
          "${AppConfig.assetsBaseURL}/${SubscriptionConstants.starBackground}",
      fit: BoxFit.cover,
      alignment: Alignment.center,
      placeholder: (context, url) => const SizedBox(),
      errorWidget: (context, url, error) => const SizedBox(),
    );
  }
}
