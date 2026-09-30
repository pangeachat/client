import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';

/// The base tiles behind every map in the app — the world map and the chat
/// location bubble. Phase 2 of world-map-tiles.instructions.md: Stadia Maps'
/// Alidade Smooth raster styles, a light and a dark one, so dark theme needs
/// no client-side filter.
class MapTiles {
  const MapTiles._();

  static String urlTemplate(Brightness brightness) =>
      'https://tiles.stadiamaps.com/tiles/'
      '${brightness == Brightness.dark ? 'alidade_smooth_dark' : 'alidade_smooth'}'
      '/{z}/{x}/{y}.png';

  /// The tiles' land colour, painted wherever a tile has not arrived (or
  /// failed), so a gap reads as unfilled map rather than a flash (#7937).
  static Color background(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF333333)
      : const Color(0xFFF2F3F0);

  /// Request headers for the tile provider. Native builds authenticate with
  /// the API key; web sends none, because Stadia checks the page's domain and
  /// needs no key on localhost. The key goes in a header rather than the URL
  /// so it never reaches tile error messages, which are sent to Sentry.
  static Map<String, String> get headers {
    final key = Environment.stadiaMapsApiKey;
    return {
      if (!kIsWeb && key != null && key.isNotEmpty)
        'Authorization': 'Stadia-Auth $key',
    };
  }

  /// The credits Stadia requires for the Alidade styles, in display order.
  static const List<MapTileCredit> credits = [
    MapTileCredit('Stadia Maps', 'https://stadiamaps.com/attribution/'),
    MapTileCredit('OpenMapTiles', 'https://openmaptiles.org/'),
    MapTileCredit('OpenStreetMap', 'https://www.openstreetmap.org/copyright'),
  ];

  /// All [credits] on one line, for a map too small for a credits popup.
  static String get creditsLine =>
      credits.map((credit) => '© ${credit.name}').join(' ');
}

class MapTileCredit {
  final String name;
  final String url;

  const MapTileCredit(this.name, this.url);
}
