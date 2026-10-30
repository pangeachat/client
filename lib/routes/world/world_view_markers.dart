import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_view_items.dart';

/// The world view's markers (org world-view doc): a city as a small city
/// icon that grows with the XP the learner has earned there, gold on the dark
/// basemap, ringed once they have finished an activity there, and an airship
/// pill, filled for a course the learner is aboard and outlined for a public
/// course they could join,
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
        // The box is centred on the coordinate with the icon at its centre,
        // so the icon is on the city. (flutter_map's alignment moves the
        // whole widget: topCenter would float the entire marker above it.)
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
        // bottom and a gap the size of the city icon, so the airship rides
        // just above the city it has reached.
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
  /// The tappable square around the icon.
  static const double hitSize = 36;

  /// A city the learner has not played is a tiny icon; it grows with the XP
  /// earned there, levelling off at [maxIconSize] so one well-played city
  /// never swallows its neighbours. Half of the growth comes by [halfXp].
  static const double minIconSize = 11;
  static const double maxIconSize = 30;
  static const int halfXp = 300;

  /// The ship pill's clearance above the city, at the largest icon.
  static const double dotSize = maxIconSize;

  static double iconSizeFor(int xp) =>
      minIconSize + (maxIconSize - minIconSize) * (xp / (xp + halfXp));

  final WorldCity city;
  final VoidCallback onTap;
  const WorldCityMarker({super.key, required this.city, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final gold = Colors.amber.shade600;
    // On the dark basemap a city is gold; a stamped one gains a ring so it
    // still stands apart from the rest.
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? gold : theme.colorScheme.primary;
    final ring = dark ? Colors.white : gold;
    final size = iconSizeFor(city.xp);
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
              width: size + 6,
              height: size + 6,
              decoration: city.stamped
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ring, width: 1.5),
                    )
                  : null,
              child: Icon(
                Symbols.location_city_rounded,
                size: size,
                fill: 1,
                color: ink,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small airship, drawn in [color]: hull, fins and a gondola. Material has
/// no airship glyph, so the pill carries its own.
class AirshipIcon extends StatelessWidget {
  static const String _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <ellipse cx="11" cy="9.5" rx="9.5" ry="5" fill="currentColor"/>
  <path d="M18.5 7.5 L23 5.5 L23 13.5 L18.5 11.5 Z" fill="currentColor"/>
  <path d="M8 14 L14 14 L13 17 L9 17 Z" fill="currentColor"/>
  <rect x="9.5" y="13.5" width="1" height="2" fill="currentColor"/>
  <rect x="12.5" y="13.5" width="1" height="2" fill="currentColor"/>
</svg>
''';
  final double size;
  final Color color;
  const AirshipIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _svg,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
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
    final fill = ship.aboard
        ? theme.colorScheme.primary
        : theme.colorScheme.surface;
    final ink = ship.aboard
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.primary;
    return Semantics(
      button: true,
      label: ship.aboard
          ? l10n.worldShipLabel(ship.name, ship.cityName)
          : l10n.worldPublicShipLabel(ship.name, ship.cityName),
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
              color: fill,
              border: ship.aboard
                  ? null
                  : Border.all(color: theme.colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 6),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AirshipIcon(size: 18, color: ink),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    ship.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: ink,
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
