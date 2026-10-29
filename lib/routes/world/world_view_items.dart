import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/course_itinerary.dart';

/// What the world view draws outside any course (org world-view doc): the
/// learner's courses as ships at the city each trip has reached, and the
/// cities along those trips, a city stamped once the learner has finished an
/// activity there. Pure over the courses' records, so the rule is testable
/// without a client; the map controller feeds it the joined courses.

/// One joined course as the world view reads it: its record and its ship's
/// position.
class CourseTripView {
  final String roomId;
  final String name;
  final CourseMissionsEvent? copy;
  final CoursePositionEvent? position;

  const CourseTripView({
    required this.roomId,
    required this.name,
    required this.copy,
    required this.position,
  });
}

/// A course on the map: at the city its trip has reached.
class WorldShip {
  final String roomId;
  final String name;
  final LatLng point;
  final String cityName;
  final String cityKey;

  const WorldShip({
    required this.roomId,
    required this.name,
    required this.point,
    required this.cityName,
    required this.cityKey,
  });
}

/// A city on a trip the learner is on, with the ships there now and whether
/// the learner has finished an activity in it.
class WorldCity {
  final String key;
  final String name;
  final LatLng point;
  final List<String> shipRoomIds;
  final bool stamped;

  const WorldCity({
    required this.key,
    required this.name,
    required this.point,
    required this.shipRoomIds,
    required this.stamped,
  });
}

/// One key per listed city, from its recorded position (integer
/// microdegrees), so two courses at the same city share one marker.
String cityKeyOf(MissionCity city) => '${city.latE6}/${city.lngE6}';

/// The learner's courses as ships: one per course whose record is a trip
/// and whose ship's stop has a city. A course without a trip, or at a stop
/// with no listed city, has no ship yet.
List<WorldShip> shipsOf(Iterable<CourseTripView> courses, DateTime now) {
  final ships = <WorldShip>[];
  for (final course in courses) {
    final copy = course.copy;
    if (copy == null) continue;
    final stop = CourseItinerary.shipStopOf(copy, course.position, now);
    if (stop == null) continue;
    final city = copy.missions[stop].city;
    if (city == null) continue;
    ships.add(
      WorldShip(
        roomId: course.roomId,
        name: course.name,
        point: city.point,
        cityName: city.name,
        cityKey: cityKeyOf(city),
      ),
    );
  }
  return ships;
}

/// The cities along the learner's trips, each once, with the ships there
/// and the gold stamp when one of the learner's saved activities belongs to
/// a Mission at that city.
List<WorldCity> citiesOf(
  Iterable<CourseTripView> courses,
  Set<String> savedActivityIds,
  DateTime now,
) {
  final ships = shipsOf(courses, now);
  final byKey = <String, ({MissionCity city, bool stamped})>{};
  for (final course in courses) {
    final copy = course.copy;
    if (copy == null || !copy.isTrip) continue;
    for (final mission in copy.missions) {
      final city = mission.city;
      if (city == null) continue;
      final key = cityKeyOf(city);
      final stamped = mission.activityIds.any(savedActivityIds.contains);
      final seen = byKey[key];
      byKey[key] = (city: city, stamped: stamped || (seen?.stamped ?? false));
    }
  }
  return [
    for (final MapEntry(:key, :value) in byKey.entries)
      WorldCity(
        key: key,
        name: value.city.name,
        point: value.city.point,
        shipRoomIds: [
          for (final ship in ships)
            if (ship.cityKey == key) ship.roomId,
        ],
        stamped: value.stamped,
      ),
  ];
}
