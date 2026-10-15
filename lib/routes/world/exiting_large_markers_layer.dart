import 'package:flutter/widgets.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/routes/world/world_map_activity_card.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_view.dart';

class ExitingLargeMarkersLayer {
  final List<LargeCardSnapshot> exitingLarge;
  final void Function(String) onExited;

  const ExitingLargeMarkersLayer({
    required this.exitingLarge,
    required this.onExited,
  });

  MarkerLayer layer() {
    final cards = exitingLarge.where((s) => s.card.point != null);
    return MarkerLayer(
      markers: cards.map((snap) {
        const tier = PinTier.large;
        final standsOnStamp = snap.starLevel != ActivityStarLevel.none;
        final box = kMapActivityCards
            ? PinSize.mapCardBox(standsOnStamp: standsOnStamp)
            : Size(
                tier.dotWidth + WorldMapLargeCard.badgeOverhang * 2,
                tier.dotHeight(snap.state) +
                    WorldMapLargeCard.tailHeight +
                    WorldMapLargeCard.badgeOverhang,
              );
        return Marker(
          point: snap.card.point!,
          width: box.width,
          height: box.height,
          alignment: Alignment.topCenter,
          // Child key, never Marker.key — see dot_markers_layer.dart
          // (#7947/#8136).
          child: Align(
            key: ValueKey('exiting_large_${snap.card.activityId}'),
            alignment: Alignment.bottomCenter,
            child: WorldMapLargeCardAnimated(
              dying: true,
              onExited: () => onExited(snap.card.activityId),
              child: kMapActivityCards
                  ? WorldMapActivityCard(
                      card: snap.card,
                      state: snap.state,
                      plan: snap.plan,
                      starsEarned: snap.starsEarned,
                      participants: snap.participants,
                      openSlots: snap.openSlots,
                      standsOnStamp: standsOnStamp,
                      // No interaction on a card that's on its way out.
                      onTap: () {},
                    )
                  : WorldMapLargeCard(
                      card: snap.card,
                      state: snap.state,
                      pinged: snap.pinged,
                      plan: snap.plan,
                      liveRoom: snap.liveRoom,
                      starsEarned: snap.starsEarned,
                      participants: snap.participants,
                      openSlots: snap.openSlots,
                      starLevel: snap.starLevel,
                      understaffed: snap.understaffed,
                      // No interaction on a card that's on its way out.
                      onTap: () {},
                      onClose: null,
                    ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
