import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// A listed city: one row of the CMS `cities` collection, the one list every
/// app names a place by (org quests-and-learning-objectives doc, "A course is
/// a trip"; admin-dash-api public-plan doc, "Places are named by their
/// nearest listed city").
class ListedCity {
  final String key;
  final String name;
  final String country;
  final double lat;
  final double lng;

  // Unit vector on the sphere: the nearest city is the one with the largest
  // dot product, which avoids a haversine per pair.
  final double _x;
  final double _y;
  final double _z;

  ListedCity({
    required this.key,
    required this.name,
    required this.country,
    required this.lat,
    required this.lng,
  }) : _x = math.cos(_rad(lat)) * math.cos(_rad(lng)),
       _y = math.cos(_rad(lat)) * math.sin(_rad(lng)),
       _z = math.sin(_rad(lat));

  LatLng get point => LatLng(lat, lng);

  /// A row of the collection (or of its seed); null for a row that cannot be
  /// placed or named, which is dropped rather than drawn at 0,0.
  static ListedCity? tryParse(Object? row) {
    if (row is! Map) return null;
    final key = row['key'] ?? row['id'];
    final name = row['name'];
    final country = row['country'];
    final lat = _finite(row['lat']);
    final lng = _finite(row['lng']);
    if (key is! String ||
        key.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        country is! String ||
        lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return null;
    }
    return ListedCity(
      key: key,
      name: name.trim(),
      country: country.trim(),
      lat: lat,
      lng: lng,
    );
  }

  static double? _finite(Object? value) {
    if (value is bool || value is! num) return null;
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }
}

double _rad(double degrees) => degrees * math.pi / 180;

/// The listed cities and the one rule that names a point by them: the nearest
/// listed city within [capMiles], and no city beyond that. The same rule as
/// admin-dash-api's `app/plan/cities.py`, checked against the same example set
/// (`test/pangea/fixtures/nearest_city.json`).
class CityIndex {
  /// A point further than this from every listed city belongs to no city.
  static const double capMiles = 250;
  static const double earthRadiusMiles = 3958.7613;

  // The cap as the cosine of its central angle: two unit vectors' dot product
  // is the cosine of the angle between them, so a city is within the cap
  // exactly when its dot product with the point is at least this.
  static final double _capCos = math.cos(capMiles / earthRadiusMiles);

  final List<ListedCity> cities;
  final Map<String, ListedCity?> _answers = {};

  CityIndex(Iterable<ListedCity> cities) : cities = List.unmodifiable(cities);

  /// An index over the parseable rows, each key once (the first wins).
  factory CityIndex.fromRows(Iterable<Object?> rows) {
    final seen = <String>{};
    final cities = <ListedCity>[];
    for (final row in rows) {
      final city = ListedCity.tryParse(row);
      if (city != null && seen.add(city.key)) cities.add(city);
    }
    return CityIndex(cities);
  }

  int get length => cities.length;

  /// The listed city nearest [point] when it is within [capMiles] (on the
  /// sphere), else null. Points are rounded to about 100 m so activities
  /// sharing a place share one lookup.
  ListedCity? nearest(LatLng point) {
    final lat = (point.latitude * 1000).round() / 1000;
    final lng = (point.longitude * 1000).round() / 1000;
    final cacheKey = '$lat,$lng';
    if (_answers.containsKey(cacheKey)) return _answers[cacheKey];
    final x = math.cos(_rad(lat)) * math.cos(_rad(lng));
    final y = math.cos(_rad(lat)) * math.sin(_rad(lng));
    final z = math.sin(_rad(lat));
    ListedCity? best;
    var bestDot = _capCos;
    for (final city in cities) {
      final dot = city._x * x + city._y * y + city._z * z;
      if (dot > bestDot) {
        best = city;
        bestDot = dot;
      }
    }
    if (_answers.length < 50000) _answers[cacheKey] = best;
    return best;
  }

  /// Great-circle distance in miles, for tests and the example set's edges.
  static double milesBetween(LatLng a, LatLng b) {
    final ax = math.cos(_rad(a.latitude)) * math.cos(_rad(a.longitude));
    final ay = math.cos(_rad(a.latitude)) * math.sin(_rad(a.longitude));
    final az = math.sin(_rad(a.latitude));
    final bx = math.cos(_rad(b.latitude)) * math.cos(_rad(b.longitude));
    final by = math.cos(_rad(b.latitude)) * math.sin(_rad(b.longitude));
    final bz = math.sin(_rad(b.latitude));
    final dot = (ax * bx + ay * by + az * bz).clamp(-1.0, 1.0);
    return math.acos(dot) * earthRadiusMiles;
  }
}
