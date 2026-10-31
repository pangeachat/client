import 'package:latlong2/latlong.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/course_itinerary.dart';

/// What the world view draws outside any course (org world-view doc): the
/// learner's courses as ships at the city each trip has reached, and the
/// cities along those trips, each sized by the XP the learner has earned there
/// and stamped once they have finished an activity. Pure over the courses' records, so the rule is testable
/// without a client; the map controller feeds it the joined courses.

/// One course as the world view reads it: its record and its ship's
/// position, and whether the learner is aboard (a joined room) or sees it
/// from the public catalog.
class CourseTripView {
  final String roomId;
  final String name;
  final CourseMissionsEvent? copy;
  final CoursePositionEvent? position;
  final bool aboard;

  /// The Can-Do ids of the Missions open to the learner on this course
  /// (`CourseItinerary.openMissionIdsOf`), or null when nothing is closed:
  /// a course they are not aboard, not a trip, or progress not known yet.
  final Set<String>? openMissionIds;

  const CourseTripView({
    required this.roomId,
    required this.name,
    required this.copy,
    required this.position,
    this.aboard = true,
    this.openMissionIds,
  });
}

/// The learner's [joined] courses with the [public] catalog behind them: a
/// course in both is read from its joined room, whose state is fresher than
/// the catalog's cache, so one room is one ship.
List<CourseTripView> mergeTrips(
  Iterable<CourseTripView> joined,
  Iterable<CourseTripView> public,
) {
  final seen = <String>{};
  return [
    for (final course in joined)
      if (seen.add(course.roomId)) course,
    for (final course in public)
      if (seen.add(course.roomId)) course,
  ];
}

/// A course on the map: at the city its trip has reached. [aboard] when the
/// learner is in it; a ship they are aboard opens its course, any other
/// opens the course to join.
class WorldShip {
  final String roomId;
  final String name;
  final LatLng point;
  final String cityName;
  final String cityKey;
  final bool aboard;

  const WorldShip({
    required this.roomId,
    required this.name,
    required this.point,
    required this.cityName,
    required this.cityKey,
    required this.aboard,
  });
}

/// A city on a trip the learner is on, with the ships there now, the XP the
/// learner has earned in its activities, and whether they have finished one.
class WorldCity {
  final String key;
  final String name;
  final LatLng point;
  final List<String> shipRoomIds;

  /// The learner's activity XP summed over the city's Missions' activities
  /// (`Client.userXpByActivity`). The dot grows with it.
  final int xp;

  /// A course the learner is aboard has a Mission here: the one condition
  /// for zooming all the way into the city.
  final bool aboard;

  /// Aboard, and every such Mission is closed to the learner (org quests
  /// doc, "Progression"): the city wears a lock.
  final bool locked;

  const WorldCity({
    required this.key,
    required this.name,
    required this.point,
    required this.shipRoomIds,
    required this.xp,
    this.aboard = false,
    this.locked = false,
  });

  /// Finished an activity here: a saved session banks XP, so any XP at all
  /// is the stamp.
  bool get stamped => xp > 0;
}

/// One key per listed city, from its recorded position (integer
/// microdegrees), so two courses at the same city share one marker.
String cityKeyOf(MissionCity city) => '${city.latE6}/${city.lngE6}';

/// The courses as ships: one per course whose record is a trip
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
        aboard: course.aboard,
      ),
    );
  }
  return ships;
}

/// The cities along the learner's trips, each once, with the [ships] there
/// (from [shipsOf] over the same courses) and the learner's XP in the city's
/// activities ([xpByActivity], `Client.userXpByActivity`), which sizes the
/// dot and, once above zero, stamps it. An activity two courses both list
/// counts once.
List<WorldCity> citiesOf(
  Iterable<CourseTripView> courses,
  Map<String, int> xpByActivity,
  List<WorldShip> ships,
) {
  final byKey =
      <
        String,
        ({MissionCity city, Set<String> activityIds, bool aboard, bool open})
      >{};
  for (final course in courses) {
    final copy = course.copy;
    if (copy == null || !copy.isTrip) continue;
    for (final mission in copy.missions) {
      final city = mission.city;
      if (city == null) continue;
      final key = cityKeyOf(city);
      final seen = byKey[key];
      // Open to the learner unless a course they are aboard names this
      // Mission closed; a public course locks nothing.
      final open =
          course.aboard &&
          (course.openMissionIds?.contains(mission.loId) ?? true);
      byKey[key] = (
        city: city,
        activityIds: {...?seen?.activityIds, ...mission.activityIds},
        aboard: course.aboard || (seen?.aboard ?? false),
        open: open || (seen?.open ?? false),
      );
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
        xp: value.activityIds.fold(
          0,
          (sum, id) => sum + (xpByActivity[id] ?? 0),
        ),
        aboard: value.aboard,
        locked: value.aboard && !value.open,
      ),
  ];
}

/// The world view's ships and cities over [courses], each course read once.
({List<WorldShip> ships, List<WorldCity> cities}) worldViewOf(
  List<CourseTripView> courses,
  Map<String, int> xpByActivity,
  DateTime now,
) {
  final ships = shipsOf(courses, now);
  return (ships: ships, cities: citiesOf(courses, xpByActivity, ships));
}

/// The activities at the city [cityKey], from every Mission placed there
/// across [courses] (the learner's own and the public catalog's), each once
/// and in Mission order. The city card's carousel; the slicer's own placement
/// of each Mission, never a second point-to-city match.
List<String> activityIdsAtCity(
  Iterable<CourseTripView> courses,
  String cityKey,
) {
  final ids = <String>{};
  for (final course in courses) {
    final copy = course.copy;
    if (copy == null) continue;
    for (final mission in copy.missions) {
      final city = mission.city;
      if (city == null || cityKeyOf(city) != cityKey) continue;
      ids.addAll(mission.activityIds);
    }
  }
  return ids.toList();
}
