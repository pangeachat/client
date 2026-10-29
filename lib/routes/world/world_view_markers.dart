import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_view_items.dart';

/// The world view's markers (org world-view doc): a city as a small circle,
/// gold-ringed once the learner has finished an activity there, and a ship
/// carrying its course's name at the city its trip has reached. A ship opens
/// its course; a city brings the map down into it.
class WorldViewLayer {
  final List<WorldCity> cities;
  final List<WorldShip> ships;
  final void Function(WorldCity city) onCityTap;
  final void Function(WorldShip ship) onShipTap;

  const WorldViewLayer({
    required this.cities,
    required this.ships,
    required this.onCityTap,
    required this.onShipTap,
  });

  Widget layer() => MarkerLayer(
    markers: [
      for (final city in cities)
        // The box is centred on the coordinate and the dot sits at its
        // vertical centre, so the dot is on the city and the label hangs
        // below it. (flutter_map's alignment moves the whole widget: topCenter
        // would float the entire marker above the city.)
        Marker(
          point: city.point,
          width: 120,
          height: WorldCityMarker.height,
          alignment: Alignment.center,
          child: WorldCityMarker(
            key: ValueKey('city:${city.key}'),
            city: city,
            onTap: () => onCityTap(city),
          ),
        ),
      // Ships paint over cities: a ship is the thing to find.
      for (final ship in ships)
        // The whole box sits above the coordinate, with the pill at its
        // bottom and a gap the size of the city dot, so the ship rides just
        // above the city it has reached.
        Marker(
          point: ship.point,
          width: 180,
          height: WorldShipMarker.height,
          alignment: Alignment.topCenter,
          child: WorldShipMarker(
            key: ValueKey('ship:${ship.roomId}'),
            ship: ship,
            onTap: () => onShipTap(ship),
          ),
        ),
    ],
  );
}

class WorldCityMarker extends StatelessWidget {
  static const double height = 60;
  static const double dotSize = 18;
  final WorldCity city;
  final VoidCallback onTap;
  const WorldCityMarker({super.key, required this.city, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final gold = Colors.amber.shade600;
    return Semantics(
      button: true,
      label: city.stamped
          ? l10n.worldCityVisitedLabel(city.name)
          : l10n.worldCityLabel(city.name),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Puts the dot's centre at the box's centre, i.e. on the point.
            const SizedBox(height: height / 2 - dotSize / 2),
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: city.stamped ? gold : theme.colorScheme.primary,
                  width: city.stamped ? 3 : 2,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                city.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: city.stamped ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorldShipMarker extends StatelessWidget {
  static const double height = 48;
  final WorldShip ship;
  final VoidCallback onTap;
  const WorldShipMarker({super.key, required this.ship, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Semantics(
      button: true,
      label: l10n.worldShipLabel(ship.name, ship.cityName),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.only(
              bottom: WorldCityMarker.dotSize / 2 + 2,
            ),
            padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 6),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sailing,
                  size: 16,
                  color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    ship.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
