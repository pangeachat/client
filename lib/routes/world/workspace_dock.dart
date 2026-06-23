import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// The shared "floating dock" chrome for the world_v2 workspace edges — the
/// left navigation rail and the top-right user cluster. Both are rounded,
/// surface-coloured, lightly elevated, outline-bordered pills floating over the
/// persistent map. This is the **single source of truth** for that style so the
/// two sides always match (same border radius, elevation, surface, border).
///
/// The [child] supplies the dock's content (the rail's items, the cluster's
/// trackers). Clipped to the rounded shape so item fills, selection highlights,
/// and scrolled content stay inside the curved corners. See
/// `routing.instructions.md`.
class WorkspaceDock extends StatelessWidget {
  final Widget child;

  const WorkspaceDock({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
        ),
        child: child,
      ),
    );
  }
}
