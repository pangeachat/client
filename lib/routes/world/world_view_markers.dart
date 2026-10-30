import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_view_items.dart';

/// The world view's markers (org world-view doc): a city as a tiny circle
/// that grows with the XP the learner has earned there, gold-ringed once they
/// have finished an activity (a solid gold dot on the dark basemap,
/// light-ringed once stamped), and a ship
/// carrying its course's name at the city its trip has reached. A ship opens
/// its course; a city brings the map down into it. A city carries no label of
/// its own: the basemap already names it, and its name stays available to
/// screen readers and as a hover tooltip.
class WorldViewLayer {
  /// The ships and cities to draw ([worldViewOf]).
  final ({List<WorldShip> ships, List<WorldCity> cities}) view;
  final void Function(WorldCity city) onCityTap;
  final void Function(WorldShip ship) onShipTap;

  const WorldViewLayer({
    required this.view,
    required this.onCityTap,
    required this.onShipTap,
  });

  List<WorldCity> get cities => view.cities;
  List<WorldShip> get ships => view.ships;

  Widget layer() => MarkerLayer(
    markers: [
      for (final city in cities)
        // The box is centred on the coordinate with the dot at its centre, so
        // the dot is on the city. (flutter_map's alignment moves the whole
        // widget: topCenter would float the entire marker above the city.)
        Marker(
          point: city.point,
          width: WorldCityMarker.hitSize,
          height: WorldCityMarker.hitSize,
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
  /// The tappable square around the dot.
  static const double hitSize = 28;

  /// A city the learner has not played is a tiny dot; it grows with the XP
  /// earned there, levelling off at [maxDotSize] so one well-played city
  /// never swallows its neighbours. Half of the growth comes by [halfXp].
  static const double minDotSize = 5;
  static const double maxDotSize = 20;
  static const int halfXp = 300;

  /// The ship pill's clearance above the city, at the largest dot.
  static const double dotSize = maxDotSize;

  static double dotSizeFor(int xp) =>
      minDotSize + (maxDotSize - minDotSize) * (xp / (xp + halfXp));
  final WorldCity city;
  final VoidCallback onTap;
  const WorldCityMarker({super.key, required this.city, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final gold = Colors.amber.shade600;
    // On the dark basemap a city is a solid gold dot, no hollow centre; a
    // stamped one gains a light ring so it still stands apart from the rest.
    final dark = theme.brightness == Brightness.dark;
    final fill = dark ? gold : theme.colorScheme.surface;
    final ring = dark
        ? (city.stamped ? Colors.white : gold)
        : (city.stamped ? gold : theme.colorScheme.primary);
    return Semantics(
      button: true,
      label: city.stamped
          ? l10n.worldCityVisitedLabel(city.name)
          : l10n.worldCityLabel(city.name),
      child: Tooltip(
        message: city.name,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Container(
              width: dotSizeFor(city.xp),
              height: dotSizeFor(city.xp),
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: ring,
                  width: city.stamped ? 2.5 : 1.5,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4),
                ],
              ),
            ),
          ),
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
              bottom: WorldCityMarker.dotSize / 2 + 4,
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
