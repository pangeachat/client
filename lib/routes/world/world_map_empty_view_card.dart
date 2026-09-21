import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_filter.dart';

/// The world map's empty-view card, driven by the controller's diagnosis
/// ([MapEmptyVerdict]): one message per scenario, each offering exactly the
/// remedy that fixes it — Zoom out when the matches exist but sit outside the
/// viewport, Widen search when the pills are the excluder, and no lever at all
/// when nothing would help (a query matching nothing). Zoom out leads and is
/// DISABLED (not hidden) when it can't run, so the card never dangles a dead
/// action. Presentational: the hosts decide when it mounts and
/// where the callbacks route; rendering [MapEmptyVerdict.none] draws nothing.
class WorldMapEmptyViewCard extends StatelessWidget {
  final MapEmptyVerdict verdict;

  /// The camera is above its zoom-out floor. It gates the lever only for
  /// [MapEmptyVerdict.noActivities] — see [build].
  final bool canZoomOut;

  /// Clear every pill to "All …" / step the camera out one zoom level.
  final VoidCallback onWidenSearch;
  final VoidCallback onZoomOut;

  /// Browse-order key for the card's semantic group — set only where the card
  /// is a top-level workspace sibling (the course-scoped map slot, #8755).
  final SemanticsSortKey? sortKey;

  const WorldMapEmptyViewCard({
    super.key,
    required this.verdict,
    required this.canZoomOut,
    required this.onWidenSearch,
    required this.onZoomOut,
    this.sortKey,
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
    // The lever runs `resetToWorld`, which RE-CENTERS as well as zooms
    // (#8121), so with matches loaded off-screen it still has work to do at
    // the zoom floor — the narrow-screen case the ticket is about, where the
    // whole world doesn't fit however far out you pull. Only the
    // nothing-loaded verdict has nothing to re-center on, so that one alone
    // greys out at the floor.
    final zoomRunnable =
        canZoomOut || verdict == MapEmptyVerdict.matchesOffscreen;

    // One named group (labeled with the message) rather than loose text +
    // button nodes, so the card is a single, keyable sibling wherever it
    // mounts (#8755).
    return Semantics(
      label: message,
      sortKey: sortKey,
      container: true,
      explicitChildNodes: true,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Text(message, style: theme.textTheme.bodyMedium),
              ),
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
                        // Greyed rather than hidden when it can't run: the
                        // card's advice stays visible either way.
                        onPressed: zoomRunnable ? onZoomOut : null,
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
      ),
    );
  }
}
