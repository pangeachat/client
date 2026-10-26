import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';

/// Names the environment across every screen while the environment switcher
/// points this build away from its own (deployment.instructions.md
/// § Environment switcher). A [Banner] paints over [child] without taking its
/// taps.
class EnvironmentBanner extends StatelessWidget {
  final Widget child;

  const EnvironmentBanner({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    if (!Environment.isSwitched) return child;
    return Banner(
      message: Environment.activeEnvironment.toUpperCase(),
      location: BannerLocation.topEnd,
      child: child,
    );
  }
}
