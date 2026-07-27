import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_view.dart';

class LargeMarkersLayer {
  final List<QuestActivityCard> largeCards;
  final Map<String, LargeCardSnapshot> currentLarge;
  final String? focusedId;
  final void Function(QuestActivityCard) onTap;
  final void Function(QuestActivityCard) onClose;

  const LargeMarkersLayer({
    required this.largeCards,
    required this.currentLarge,
    required this.focusedId,
    required this.onTap,
    required this.onClose,
  });

  MarkerLayer layer() {
    const tier = PinTier.large;
    return MarkerLayer(
      markers: largeCards
          .map((card) {
            final snap = currentLarge[card.activityId];
            if (snap == null || card.point == null) return null;
            return Marker(
              point: card.point!,
              // Widen by the badge overhang on both sides; the card centres within
              // and the pin stays at the box's horizontal centre, so the tail still
              // lands on the dot while the top-right badge has room to peek.
              width: tier.dotWidth + WorldMapLargeCard.badgeOverhang * 2,
              // The inner Align lets the card hug its own content (each state is a
              // different height: joinable/ongoingPending add the avatar row,
              // ongoingActive adds the message preview + star row). Height here is
              // only a ceiling so the tallest variant isn't clipped; shorter cards
              // don't stretch to fill it. The extra tailHeight reserves room beneath
              // the card for the pin tail; the badgeOverhang reserves room ABOVE
              // (topCenter alignment anchors the box bottom to the pin, so slack
              // lands at the top) for the peeking unread badge.
              height:
                  tier.dotHeight(snap.state) +
                  WorldMapLargeCard.tailHeight +
                  WorldMapLargeCard.badgeOverhang,
              alignment: Alignment.topCenter,
              child: Align(
                // Bottom-align so the card+tail hugs its pin (the tail tip lands on
                // the dot) instead of floating with a gap above it (#7153).
                alignment: Alignment.bottomCenter,
                child: WorldMapLargeCardAnimated(
                  child: WorldMapLargeCard(
                    card: snap.card,
                    state: snap.state,
                    pinged: snap.pinged,
                    plan: snap.plan,
                    liveRoom: snap.liveRoom,
                    starsEarned: snap.starsEarned,
                    participants: snap.participants,
                    openSlots: snap.openSlots,
                    starLevel: snap.starLevel,
                    isFocused: card.activityId == focusedId,
                    onTap: () => onTap(card),
                    onClose: () => onClose(card),
                  ),
                ),
              ),
            );
          })
          .whereType<Marker>()
          .toList(),
    );
  }
}
