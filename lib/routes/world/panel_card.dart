import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// The shared chrome for every workspace panel (world_v2): a rounded, elevated
/// surface that floats over the persistent map, with one uniform [margin]. Every
/// panel wraps its content in this so they all read as the same floating card —
/// the left/right column tokens AND the center detail (an activity, a
/// course-wizard step, a public-course preview). Keeping the rounding, elevation
/// and margin in one widget is why they can't drift apart. See
/// `routing.instructions.md`.
class PanelCard extends StatelessWidget {
  final Widget child;

  const PanelCard({super.key, required this.child});

  /// The margin every panel insets from its allocator slot (and the gap between
  /// adjacent panels is two of these horizontal insets — see [PanelAllocator]'s
  /// `panelGap`). Vertical matches the shell's chrome margin.
  static const EdgeInsets margin = EdgeInsets.symmetric(
    horizontal: 8.0,
    vertical: 12.0,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      // Clip the contained surface (a chat, a Scaffold, a card body) to the
      // rounded corners.
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}
