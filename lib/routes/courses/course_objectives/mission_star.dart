import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// A Mission's star: a dark outline while it's open, bright gold inside that
/// outline once earned — the outline carries the contrast on a light surface.
class MissionStar extends StatelessWidget {
  final bool satisfied;
  final double size;

  const MissionStar({required this.satisfied, required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: satisfied ? L10n.of(context).missionStarEarned : null,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (satisfied)
                Icon(
                  Icons.star_rounded,
                  size: size * 0.9,
                  color: theme.pangea.goldFixedDim,
                ),
              Icon(
                Icons.star_outline_rounded,
                size: size,
                color: theme.colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
