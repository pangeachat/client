import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/course_itinerary.dart';

/// The ship's stop read from the course record alone: what the map fades to
/// when a course opens (org course-view doc, "The camera").
void main() {
  CourseMission mission(String id, {DateTime? dueAt}) =>
      CourseMission(loId: id, activityIds: const ['a'], dueAt: dueAt);

  final now = DateTime.utc(2026, 11, 10);

  test('a record that is not a trip names no stop', () {
    final copy = CourseMissionsEvent(
      revision: 1,
      missions: [mission('lo1'), mission('lo2')],
    );
    expect(CourseItinerary.shipStopOf(copy, null, now), isNull);
  });

  test(
    'an undated trip is at its ship\'s position, the first stop by default',
    () {
      final copy = CourseMissionsEvent(
        revision: 1,
        version: CourseMissionsEvent.tripVersion,
        missions: [mission('lo1'), mission('lo2'), mission('lo3')],
      );
      expect(CourseItinerary.shipStopOf(copy, null, now), 0);
      expect(
        CourseItinerary.shipStopOf(
          copy,
          const CoursePositionEvent(stop: 2, fromStop: 1, since: 1),
          now,
        ),
        2,
      );
      // A position past the record's Missions is no stop at all.
      expect(
        CourseItinerary.shipStopOf(
          copy,
          const CoursePositionEvent(stop: 7, fromStop: 1, since: 1),
          now,
        ),
        isNull,
      );
    },
  );

  test('a dated trip is at the first Mission whose date is still ahead', () {
    final copy = CourseMissionsEvent(
      revision: 1,
      version: CourseMissionsEvent.tripVersion,
      startDate: DateTime.utc(2026, 11, 1),
      missions: [
        mission('lo1', dueAt: DateTime.utc(2026, 11, 5)),
        mission('lo2', dueAt: DateTime.utc(2026, 11, 15)),
        mission('lo3', dueAt: DateTime.utc(2026, 11, 25)),
      ],
    );
    expect(CourseItinerary.shipStopOf(copy, null, now), 1);
    expect(
      CourseItinerary.shipStopOf(copy, null, DateTime.utc(2026, 12, 1)),
      2,
    );
    expect(
      CourseItinerary.shipStopOf(copy, null, DateTime.utc(2026, 10, 1)),
      0,
    );
  });
}
