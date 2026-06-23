import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// The clustered-pins bubble (Google-Maps grouping), coloured by the cluster's
/// dominant state so a cluster with an open session reads green.
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
