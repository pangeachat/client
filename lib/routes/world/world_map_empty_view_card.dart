import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';

/// The world map's empty-view card, driven by the controller's diagnosis
/// ([MapEmptyVerdict]): one message per scenario, each offering exactly the
/// remedy that fixes it — Zoom out when the matches exist but sit outside the
/// viewport, Widen search when the pills are the excluder, and no lever at all
/// when nothing would help (a query matching nothing). Zoom out leads and is
/// DISABLED (not hidden) at the zoom floor, so the card never dangles an
/// action that can't run. Presentational: the hosts decide when it mounts and
/// where the callbacks route; rendering [MapEmptyVerdict.none] draws nothing.
class WorldMapEmptyViewCard extends StatelessWidget {
  final MapEmptyVerdict verdict;

  /// The camera is above its zoom-out floor; below it the zoom lever greys out.
  final bool canZoomOut;

  /// Clear every pill to "All …" / step the camera out one zoom level.
  final VoidCallback onWidenSearch;
  final VoidCallback onZoomOut;

  const WorldMapEmptyViewCard({
    super.key,
    required this.verdict,
    required this.canZoomOut,
    required this.onWidenSearch,
    required this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    final message = switch (verdict) {
      MapEmptyVerdict.none => null,
      MapEmptyVerdict.matchesOffscreen => l10n.mapMatchesOffscreen,
      MapEmptyVerdict.filtersHideMatches => l10n.mapFiltersHideMatches,
      MapEmptyVerdict.noSearchMatches => l10n.mapNoSearchMatches,
      MapEmptyVerdict.noActivities => l10n.mapNoActivitiesArea,
    };
    if (message == null) return const SizedBox.shrink();

    final offersZoom =
        verdict == MapEmptyVerdict.matchesOffscreen ||
        verdict == MapEmptyVerdict.noActivities;
    final offersWiden = verdict == MapEmptyVerdict.filtersHideMatches;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: theme.textTheme.bodyMedium),
            if (offersZoom || offersWiden) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (offersZoom)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.zoom_out, size: 16),
                      label: Text(l10n.zoomOut),
                      // Greyed at the floor rather than hidden: the card's
                      // advice stays visible even when the camera can't
                      // follow it any further.
                      onPressed: canZoomOut ? onZoomOut : null,
                    ),
                  if (offersWiden)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.filter_alt_off, size: 16),
                      label: Text(l10n.widenSearch),
                      onPressed: onWidenSearch,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
