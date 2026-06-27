import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The clustered-pins bubble (Google-Maps grouping), coloured by the cluster's
/// dominant state so a cluster with an open session reads green.
///
/// Renders statically at full size with no entry animation. The cluster package
/// ([MarkerClusterLayer]) rebuilds every cluster node — destroying and
/// recreating this widget's State, regardless of any key we set — whenever its
/// marker set changes by reference. The world map's viewport-bounded pins
/// reload and re-rank continuously while the camera pans/zooms, so that set
/// churns every few frames. A scale-in animation under those conditions reads
/// as the bubbles constantly "re-popping" (see #world-map). Individual pins
/// ([WorldMapDot]) keep their entry/exit animation; clusters are aggregates
/// that should update their count in place, not re-pop.
class WorldMapClusterBubble extends StatelessWidget {
  final int count;
  final ActivityPinState dominant;

  const WorldMapClusterBubble({
    super.key,
    required this.count,
    required this.dominant,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dominant.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
