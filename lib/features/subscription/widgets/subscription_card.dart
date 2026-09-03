import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// A surface for one piece of a subscription page's content.
///
/// The subscription surfaces paint the star art behind their content and no
/// longer wrap it in a slab, so only cards occlude the art (#8751). Anything
/// that would otherwise put text straight onto the image gets one of these.
class SubscriptionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SubscriptionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      child: child,
    );
  }
}
