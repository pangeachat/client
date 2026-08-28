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

  /// Whether this card should play its entry grow-in — false for cards
  /// already on screen at the last settle, so a State recreated by
  /// MarkerLayer's per-frame positional reconciliation doesn't replay its
  /// pop-in (#8136). Mirrors [DotMarkersLayer.animateInOf].
  final bool Function(String) animateInOf;

  const LargeMarkersLayer({
    required this.largeCards,
    required this.currentLarge,
    required this.focusedId,
    required this.onTap,
    required this.onClose,
    required this.animateInOf,
  });

  /// The large marker's box width: the card widened by the badge overhang on
  /// both sides; the card centres within and the pin stays at the box's
  /// horizontal centre, so the tail still lands on the dot while the top-right
  /// badge has room to peek. Shared with [PinSemanticsLayer] so the
  /// screen-reader mirror's rect is this same box.
  static double markerWidth() =>
      PinTier.large.dotWidth + WorldMapLargeCard.badgeOverhang * 2;

  /// The large marker's box height: a ceiling so the tallest state variant
  /// isn't clipped (the inner Align lets the card hug its own content), plus
  /// tail room beneath and badge room above. Shared with [PinSemanticsLayer].
  static double markerHeight(ActivityPinState state) =>
      PinTier.large.dotHeight(state) +
      WorldMapLargeCard.tailHeight +
      WorldMapLargeCard.badgeOverhang;

  /// Anchors the box bottom to the pin, so the height ceiling's slack lands
  /// at the top. Shared with [PinSemanticsLayer].
  static const Alignment markerAlignment = Alignment.topCenter;

  MarkerLayer layer() {
    return MarkerLayer(
      markers: largeCards
          .map((card) {
            final snap = currentLarge[card.activityId];
            if (snap == null || card.point == null) return null;
            return Marker(
              point: card.point!,
              width: markerWidth(),
              height: markerHeight(snap.state),
              alignment: markerAlignment,
              // Child key, never Marker.key — see dot_markers_layer.dart
              // (#7947/#8136). Keeps the animated card's state tied to its own
              // activity through MarkerLayer's positional reconciliation.
              child: Align(
                key: ValueKey(card.activityId),
                // Bottom-align so the card+tail hugs its pin (the tail tip lands on
                // the dot) instead of floating with a gap above it (#7153).
                alignment: Alignment.bottomCenter,
                child: WorldMapLargeCardAnimated(
                  animateIn: animateInOf(card.activityId),
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
                    understaffed: snap.understaffed,
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
