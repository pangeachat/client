import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/course_plans/cities/city_index.dart';

/// The one rule every app names a place by (admin-dash-api public-plan doc):
/// the nearest listed city within 250 miles, checked against the shared
/// example set the CMS keeps beside its seed (`scripts/data/nearest_city.json`
/// there; `tests/fixtures/` in admin-dash-api) over the real list.
void main() {
  final rows =
      jsonDecode(File('test/pangea/fixtures/cities.json').readAsStringSync())
          as List;
  final examples =
      jsonDecode(
            File('test/pangea/fixtures/nearest_city.json').readAsStringSync(),
          )
          as List;
  final index = CityIndex.fromRows(rows);

  test('the fixture list is the CMS seed: 505 cities of a million or more '
      'plus the ten hand-added places', () {
    expect(index.length, 515);
    expect(rows.where((r) => r['addedBy'] == 'seed').length, 505);
  });

  test('the example set has at least 40 points, some under no city', () {
    expect(examples.length, greaterThanOrEqualTo(40));
    expect(examples.any((e) => e['city'] == null), isTrue);
  });

  for (final example in examples) {
    final description = example['description'] as String;
    final point = LatLng(
      (example['lat'] as num).toDouble(),
      (example['lng'] as num).toDouble(),
    );
    final expected = example['city'] as Map?;
    test(description, () {
      final found = index.nearest(point);
      if (expected == null) {
        expect(found, isNull);
      } else {
        expect(found, isNotNull);
        expect(
          (found!.name, found.country),
          (expected['name'], expected['country']),
        );
        expect(
          CityIndex.milesBetween(point, found.point),
          lessThanOrEqualTo(CityIndex.capMiles),
        );
      }
    });
  }

  test('the cap is 250 miles on the sphere', () {
    final lone = CityIndex.fromRows(const [
      {
        'key': 'x',
        'name': 'Lone',
        'country': 'Nowhere',
        'lat': 0.0,
        'lng': 0.0,
      },
    ]);
    // One degree of longitude on the equator is about 69.09 miles.
    expect(lone.nearest(const LatLng(0.0, 3.6))?.name, 'Lone'); // 249 mi
    expect(lone.nearest(const LatLng(0.0, 3.64)), isNull); // 251 mi
    expect(lone.nearest(const LatLng(0.0, 180.0)), isNull);
  });

  test('rows that cannot be placed are dropped and each key kept once', () {
    final parsed = CityIndex.fromRows(const [
      {'key': 'a', 'name': 'A', 'country': 'X', 'lat': 1.0, 'lng': 1.0},
      {'key': 'a', 'name': 'A again', 'country': 'X', 'lat': 2.0, 'lng': 2.0},
      {'key': 'b', 'name': '', 'country': 'X', 'lat': 1.0, 'lng': 1.0},
      {'key': 'c', 'name': 'C', 'country': 'X', 'lat': '1', 'lng': 1.0},
      {'key': 'd', 'name': 'D', 'country': 'X', 'lat': 91.0, 'lng': 1.0},
      {'key': 'e', 'name': 'E', 'country': 'X', 'lat': true, 'lng': 1.0},
      'not a row',
    ]);
    expect(parsed.cities.map((c) => c.name), ['A']);
  });
}
