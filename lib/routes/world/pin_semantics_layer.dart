import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/large_markers_layer.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Screen-reader mirror of the drawn map pins (#7591).
///
/// The map subtree is wrapped in `ExcludeSemantics`: flutter_map's own gesture
/// detector publishes a viewport-sized tappable semantics node that blankets
/// DOM embeds layered over the map (#8013), and upstream declined to exclude
/// it (fleaflet/flutter_map#2236 — `ExcludeSemantics` around the map is their
/// recommended workaround), so the exclusion is permanent. It also drops the
/// pins' own semantics, leaving the map's "Activities" group empty to
/// assistive tech. This layer re-authors them OUTSIDE the excluded subtree:
/// one invisible semantics button per drawn pin, carrying the same label and
/// tap behavior as the visual pin.
///
/// **Each node's rect is the drawn marker's rect** — the same box size and
/// anchor alignment the marker layers hand flutter_map, laid out with
/// flutter_map's own alignment math — so a screen reader's focus highlight
/// traces the visible pin, teardrop, or card itself, not an approximate box
/// near it. `pin_semantics_layer_test.dart` pins that equality against the
/// real marker layers, so the two cannot drift apart silently.
///
/// The layer is pointer-transparent by construction: none of its render
/// objects hit-test (`Semantics` boxes over empty `SizedBox`es), so pointer
/// taps and map gestures land on the real pins as before. Deliberately NOT
/// `IgnorePointer` — that strips pointer-related semantics actions (the tap)
/// from the subtree, which is the exact loss this layer exists to repair.
/// A semantics tap (what a screen-reader double-tap sends) reaches [onTap].
class PinSemanticsLayer extends StatelessWidget {
  final MapController mapController;

  /// The pins actually drawn this frame (the budget-capped large + mid + small
  /// set), in the order they should be announced.
  final List<QuestActivityCard> cards;
  final ActivityPinState Function(String activityId) stateOf;
  final PinTier Function(String activityId) tierOf;

  /// The same box/anchor resolvers the dot marker layer is given, so dot and
  /// teardrop mirror rects are the drawn markers' rects by construction. The
  /// large tier's geometry comes from [LargeMarkersLayer]'s shared statics.
  final Size Function(ActivityPinState state, PinTier tier) markerBox;
  final Alignment Function(ActivityPinState state, PinTier tier)
  markerAlignment;

  final void Function(QuestActivityCard card) onTap;

  const PinSemanticsLayer({
    super.key,
    required this.mapController,
    required this.cards,
    required this.stateOf,
    required this.tierOf,
    required this.markerBox,
    required this.markerAlignment,
    required this.onTap,
  });

  /// The live camera, or null before the map is laid out (reading it throws
  /// until then). Pins only exist after `onMapReady`, so a null camera can
  /// only coincide with an empty [cards].
  MapCamera? get _camera {
    try {
      return mapController.camera;
    } catch (_) {
      return null;
    }
  }

  /// The on-screen rect of [card]'s drawn marker: its box placed so that the
  /// alignment anchor lands on the projected point — flutter_map's own
  /// `MarkerLayer` math, so this rect and the drawn marker coincide.
  Rect _markerRect(QuestActivityCard card, Offset projected) {
    final state = stateOf(card.activityId);
    final tier = tierOf(card.activityId);
    final Size box;
    final Alignment alignment;
    if (tier == PinTier.large) {
      box = Size(
        LargeMarkersLayer.markerWidth(),
        LargeMarkersLayer.markerHeight(state),
      );
      alignment = LargeMarkersLayer.markerAlignment;
    } else {
      box = markerBox(state, tier);
      alignment = markerAlignment(state, tier);
    }
    final anchorLeft = 0.5 * box.width * (alignment.x + 1);
    final anchorTop = 0.5 * box.height * (alignment.y + 1);
    return Rect.fromLTWH(
      projected.dx - (box.width - anchorLeft),
      projected.dy - (box.height - anchorTop),
      box.width,
      box.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      label: l10n.activities,
      container: true,
      // Follow the camera: pan/zoom moves the mirror nodes with their pins.
      child: StreamBuilder(
        stream: mapController.mapEventStream,
        builder: (context, _) {
          final camera = _camera;
          if (camera == null) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) {
              final viewport = Offset.zero & constraints.biggest;
              final children = <Widget>[];
              for (final card in cards) {
                final point = card.point;
                if (point == null) continue;
                final rect = _markerRect(
                  card,
                  camera.latLngToScreenOffset(point),
                );
                // Off-viewport pins (the camera moved since the last settle
                // re-rank) publish nothing, like the marker layers' culling.
                if (!rect.overlaps(viewport)) continue;
                children.add(
                  Positioned.fromRect(
                    rect: rect,
                    child: Semantics(
                      // Each pin is its own node; without this a lone pin
                      // merges into the "Activities" group node and its
                      // label gets the group's prefixed onto it.
                      container: true,
                      button: true,
                      label:
                          "${l10n.activityLabel(card.title)}, "
                          "${stateOf(card.activityId).label(l10n)}",
                      onTap: () => onTap(card),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              }
              return Stack(children: children);
            },
          );
        },
      ),
    );
  }
}
