import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';
import 'package:fluffychat/routes/world/world_map_view.dart';

class ExitingMarkersLayer {
  final List<PinSnapshot> exiting;
  final Size Function(ActivityPinState, PinTier) markerBox;
  final Alignment Function(ActivityPinState, PinTier) markerAlignment;
  final void Function(String) onExited;

  const ExitingMarkersLayer({
    required this.exiting,
    required this.markerBox,
    required this.markerAlignment,
    required this.onExited,
  });

  MarkerLayer layer() {
    final cards = exiting.where((p) => p.card.point != null);
    return MarkerLayer(
      markers: cards.map((p) {
        final box = markerBox(p.state, p.tier);
        return Marker(
          point: p.card.point!,
          width: box.width,
          height: box.height,
          alignment: markerAlignment(p.state, p.tier),
          child: WorldMapDot(
            card: p.card,
            state: p.state,
            tier: p.tier,
            onTap: () {},
            pinged: p.pinged,
            starLevel: p.starLevel,
            dying: true,
            onExited: () => onExited(p.card.activityId),
          ),
        );
      }).toList(),
    );
  }
}
