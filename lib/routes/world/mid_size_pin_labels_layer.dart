import 'package:flutter/widgets.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_pin_label.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

class MidSizePinLabelsLayer {
  final List<QuestActivityCard> nonLargeCards;
  final LabelSide? Function(String) sideOf;
  final Size? Function(String) sizeOf;
  final ActivityPinState Function(String) stateOf;
  final bool Function(String) nonStartableOf;
  final void Function(QuestActivityCard) onTap;

  const MidSizePinLabelsLayer({
    required this.nonLargeCards,
    required this.sideOf,
    required this.sizeOf,
    required this.stateOf,
    required this.nonStartableOf,
    required this.onTap,
  });

  /// The marker alignment that seats a label of [size] on [side] of a mid pin
  /// whose tip is the marker's point — the render-side mirror of [pinLabelRect].
  /// flutter_map's alignment is the pixel position of the point inside the box
  /// ([Marker.computePixelAlignment]); values outside [-1,1] push the box fully
  /// beside the head with no clamping.
  Alignment _labelAlignment(LabelSide side, Size size) {
    final headR = PinSize.midDiameter / 2;
    final left = side == LabelSide.right
        ? -(headR + kPinLabelGap)
        : headR + kPinLabelGap + size.width;
    final top = PinSize.midPointHeight + headR + size.height / 2;
    return Marker.computePixelAlignment(
      width: size.width,
      height: size.height,
      left: left,
      top: top,
    );
  }

  MarkerLayer layer() {
    /// The activity-name labels for the mid pins the placement pass kept — each a
    /// marker anchored at the pin's point, offset to its chosen side. The label
    /// box is measured tight to its text, so it opens ITS OWN activity on tap
    /// (not the neighbour pin it may sit over — #7920); it paints above the dot
    /// layer, so this tap wins over any pin beneath.
    final markers = nonLargeCards
        .map((card) {
          final id = card.activityId;
          final side = sideOf(id);
          final size = sizeOf(id);
          if (side == null || size == null) return null;
          return Marker(
            point: card.point!,
            width: size.width,
            height: size.height,
            alignment: _labelAlignment(side, size),
            // Child key, never Marker.key — see dot_markers_layer.dart: a
            // Marker.key duplicates across world copies at min zoom (#7947);
            // the child key keeps the label's GestureDetector state tied to
            // its own activity through MarkerLayer's per-frame positional
            // reconciliation (#8136).
            child: Opacity(
              key: ValueKey('label_$id'),
              // Match the pin: a non-startable available pin's label dims too.
              opacity: nonStartableOf(id) ? 0.5 : 1.0,
              // ExcludeSemantics: the pin's own Semantics(button) node stays the
              // single a11y activation target, so the label adds no duplicate
              // node. Opaque so the whole (text-tight) box is tappable, not just
              // painted glyph pixels; the tap-only recognizer still yields to
              // the map's drag recognizer, so panning from a label is unaffected.
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(card),
                  child: WorldMapPinLabel(
                    title: card.title,
                    color: stateOf(id).labelColor,
                  ),
                ),
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();
    return MarkerLayer(markers: markers);
  }
}
