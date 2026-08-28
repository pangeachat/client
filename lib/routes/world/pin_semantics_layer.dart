import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
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
/// one invisible semantics button per drawn pin, at the pin's projected screen
/// position, carrying the same label and tap behavior as the visual pin.
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
  final void Function(QuestActivityCard card) onTap;

  const PinSemanticsLayer({
    super.key,
    required this.mapController,
    required this.cards,
    required this.stateOf,
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
              final size = constraints.biggest;
              const box = PinSize.dotTouchTarget;
              final children = <Widget>[];
              for (final card in cards) {
                final point = card.point;
                if (point == null) continue;
                final offset = camera.latLngToScreenOffset(point);
                // Off-viewport pins (the camera moved since the last settle
                // re-rank) publish nothing, like the marker layers' culling.
                if (offset.dx < 0 ||
                    offset.dy < 0 ||
                    offset.dx > size.width ||
                    offset.dy > size.height) {
                  continue;
                }
                children.add(
                  Positioned(
                    left: offset.dx - box / 2,
                    top: offset.dy - box / 2,
                    width: box,
                    height: box,
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
