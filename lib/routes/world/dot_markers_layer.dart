import 'package:flutter/widgets.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/routes/world/world_map_large_card.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/routes/world/world_map_state_dot.dart';

class DotMarkersLayer {
  final List<QuestActivityCard> nonLargeCards;
  final PinTier Function(String) tierOf;
  final ActivityPinState Function(String) stateOf;
  final ActivityStarLevel Function(String) starLevelOf;
  final bool Function(String) nonStartableOf;
  final bool Function(String) pingedOf;
  final Room? Function(String)? activeActivityInstance;
  final Size Function(ActivityPinState, PinTier) markerBox;
  final Alignment Function(ActivityPinState, PinTier) markerAlignment;
  final String? focusedId;
  final void Function(QuestActivityCard) onTap;
  final ({List<LargeCardParticipant> participants, int openSlots}) Function(
    String,
    ActivityPinState,
  )
  sessionParticipants;

  const DotMarkersLayer({
    required this.nonLargeCards,
    required this.tierOf,
    required this.stateOf,
    required this.starLevelOf,
    required this.nonStartableOf,
    required this.pingedOf,
    required this.activeActivityInstance,
    required this.markerBox,
    required this.markerAlignment,
    required this.focusedId,
    required this.onTap,
    required this.sessionParticipants,
  });

  /// The mid-pin "num/num" participant counts for `joinable`/`ongoingPending`
  /// (world-map.instructions.md, "Pin display") — derived from the shared
  /// [_sessionParticipants] resolver so they match the large card's row.
  /// Null/null for every other state, or when the counts aren't resolvable yet.
  ({int? filled, int? total}) _participantCounts(
    String activityId,
    ActivityPinState state,
  ) {
    final (:participants, :openSlots) = sessionParticipants(activityId, state);
    final filled = participants.length;
    final total = filled + openSlots;
    return total > 0
        ? (filled: filled, total: total)
        : (filled: null, total: null);
  }

  /// The learner's own live room for an `ongoingActive` pin (world-map.
  /// instructions.md, "Pin state") — null (badge hidden) for every other
  /// state.
  Room? _unreadRoomFor(String activityId, ActivityPinState state) {
    if (state != ActivityPinState.ongoingActive) return null;
    return activeActivityInstance?.call(activityId);
  }

  /// The rendered small/mid pins, each an individual marker (no clustering).
  /// Tapping any pin opens/focuses the activity in one step (no tap-to-peek).
  /// Small dots are emitted before mid pins so mid always paints on top —
  /// markers later in the list draw over earlier ones, and "small pins should
  /// never show on top of mid pins" (world-map.instructions.md, "Pin display").
  MarkerLayer layer() {
    // Small dots first, then mid pins, each tier keeping its score order — a
    // stable partition (Dart's List.sort is not guaranteed stable) so mid
    // always paints over small without reshuffling same-tier pins frame to
    // frame.
    final cards = nonLargeCards;
    final ordered = [
      ...cards.where((c) => tierOf(c.activityId) == PinTier.small),
      ...cards.where((c) => tierOf(c.activityId) != PinTier.small),
    ];
    return MarkerLayer(
      markers: ordered.map((card) {
        final state = stateOf(card.activityId);
        final tier = tierOf(card.activityId);
        final box = markerBox(state, tier);
        final counts = _participantCounts(card.activityId, state);

        return Marker(
          point: card.point!,
          width: box.width,
          height: box.height,
          alignment: markerAlignment(state, tier),
          child: Opacity(
            opacity: nonStartableOf(card.activityId) ? 0.5 : 1.0,
            child: WorldMapDot(
              card: card,
              state: state,
              tier: tier,
              onTap: () => onTap(card),
              pinged: pingedOf(card.activityId),
              starLevel: starLevelOf(card.activityId),
              unreadRoom: _unreadRoomFor(card.activityId, state),
              participantsFilled: counts.filled,
              participantsTotal: counts.total,
              isFocused: card.activityId == focusedId,
            ),
          ),
        );
      }).toList(),
    );
  }
}
