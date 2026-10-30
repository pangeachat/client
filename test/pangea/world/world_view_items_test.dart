import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/course_itinerary.dart';
import 'package:fluffychat/routes/world/world_view_items.dart';

/// The world view's items (org world-view doc): the learner's courses as
/// ships at the city each trip has reached, and the cities along those trips,
/// stamped where the learner has finished an activity.
void main() {
  const oaxaca = MissionCity(name: 'Oaxaca', latE6: 17065400, lngE6: -96726600);
  const cdmx = MissionCity(
    name: 'Mexico City',
    latE6: 19444400,
    lngE6: -99132900,
  );
  const madrid = MissionCity(name: 'Madrid', latE6: 40402000, lngE6: -3685300);
  final now = DateTime.utc(2026, 11, 10);

  CourseMissionsEvent trip(List<(String, List<String>, MissionCity?)> stops) =>
      CourseMissionsEvent(
        revision: 1,
        version: CourseMissionsEvent.tripVersion,
        missions: [
          for (final (lo, acts, city) in stops)
            CourseMission(loId: lo, activityIds: acts, city: city),
        ],
      );

  final spanish = CourseTripView(
    roomId: '!es:x',
    name: 'Spanish 101',
    copy: trip([
      ('lo1', ['a1', 'a2'], oaxaca),
      ('lo2', ['b1'], cdmx),
      ('lo3', ['c1'], madrid),
    ]),
    position: const CoursePositionEvent(stop: 1, fromStop: 0, since: 1),
  );
  final second = CourseTripView(
    roomId: '!es2:x',
    name: 'Viaje',
    copy: trip([
      ('lo9', ['z1'], cdmx),
    ]),
    position: null,
  );
  const legacy = CourseTripView(
    roomId: '!old:x',
    name: 'Old course',
    copy: CourseMissionsEvent(
      revision: 1,
      missions: [
        CourseMission(loId: 'lo', activityIds: ['q']),
      ],
    ),
    position: null,
  );

  test(
    'a ship sits at the city its trip has reached; a course without a trip has none',
    () {
      final ships = shipsOf([spanish, second, legacy], now);
      expect(ships.map((s) => s.name), ['Spanish 101', 'Viaje']);
      expect(ships.first.cityName, 'Mexico City');
      expect(ships.last.cityName, 'Mexico City');
    },
  );

  test(
    'cities appear once each with the ships there, stamped where the learner played',
    () {
      final cities = citiesOf(
        [spanish, second, legacy],
        {'a2'},
        shipsOf([spanish, second, legacy], now),
      );
      expect(cities.map((c) => c.name), ['Oaxaca', 'Mexico City', 'Madrid']);
      final oax = cities.firstWhere((c) => c.name == 'Oaxaca');
      expect(oax.stamped, isTrue);
      expect(oax.shipRoomIds, isEmpty);
      final mex = cities.firstWhere((c) => c.name == 'Mexico City');
      expect(mex.stamped, isFalse);
      expect(mex.shipRoomIds, ['!es:x', '!es2:x']);
    },
  );

  test('a stop with no listed city puts no ship on the map', () {
    final unplaced = CourseTripView(
      roomId: '!u:x',
      name: 'Unplaced',
      copy: trip([
        ('lo1', ['a'], null),
      ]),
      position: null,
    );
    expect(shipsOf([unplaced], now), isEmpty);
    expect(citiesOf([unplaced], const {}, shipsOf([unplaced], now)), isEmpty);
  });
}
