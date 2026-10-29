import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/course_itinerary.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';

/// Which Missions are open on a course's trip (org quests doc,
/// "Progression"; pangeachat/.github#780): by the calendar with dates, by
/// progress without; a completed or teacher-opened Mission is always open;
/// a course that is not a trip closes nothing.
void main() {
  final now = DateTime.utc(2026, 11, 10, 12);

  QuestObjectiveGroup mission(String id, {DateTime? dueAt}) =>
      QuestObjectiveGroup(
        objective: LearningObjective(id: id, objective: id),
        activities: const [],
        pacing: dueAt == null ? null : MissionPacing(dueAt: dueAt),
      );

  Set<String>? open({
    required List<QuestObjectiveGroup> groups,
    required CourseTrip? trip,
    bool progressResolved = true,
    String? anchorId,
    Set<String> completed = const {},
    Set<String> reopened = const {},
  }) => CourseItinerary.openMissionIds(
    groups: groups,
    trip: trip,
    now: now,
    progressResolved: progressResolved,
    anchorId: anchorId,
    completedIds: completed,
    reopenedIds: reopened,
  );

  group('a course that is not a trip', () {
    test('closes nothing', () {
      expect(open(groups: [mission('a'), mission('b')], trip: null), isNull);
    });
  });

  group('an undated trip (by progress)', () {
    const trip = CourseTrip();
    final groups = [mission('a'), mission('b'), mission('c'), mission('d')];

    test('opens every Mission up to the first incomplete one', () {
      expect(open(groups: groups, trip: trip, anchorId: 'a'), {'a'});
      expect(open(groups: groups, trip: trip, anchorId: 'c'), {'a', 'b', 'c'});
    });

    test('with every Mission complete, every one is open', () {
      expect(open(groups: groups, trip: trip, anchorId: null), {
        'a',
        'b',
        'c',
        'd',
      });
    });

    test('locks nothing before progress is known', () {
      expect(open(groups: groups, trip: trip, progressResolved: false), isNull);
    });

    test('a completed or teacher-opened Mission stays open', () {
      expect(
        open(
          groups: groups,
          trip: trip,
          anchorId: 'a',
          completed: {'c'},
          reopened: {'d'},
        ),
        {'a', 'c', 'd'},
      );
    });
  });

  group('a dated trip (by the calendar)', () {
    final trip = CourseTrip(startDate: DateTime.utc(2026, 11, 2));
    final groups = [
      mission('a', dueAt: DateTime.utc(2026, 11, 8)),
      mission('b', dueAt: DateTime.utc(2026, 11, 15)),
      mission('c', dueAt: DateTime.utc(2026, 11, 22)),
      mission('d'),
    ];

    test('the course is at the first Mission whose date is still ahead, '
        'and everything up to it is open', () {
      expect(CourseItinerary.datedStop(groups, now), 1);
      expect(open(groups: groups, trip: trip), {'a', 'b'});
    });

    test('before the start date only the first city is open', () {
      final early = CourseTrip(startDate: DateTime.utc(2026, 12, 1));
      expect(open(groups: groups, trip: early), {'a'});
    });

    test('after the last date the course sits at its last city', () {
      final later = [
        mission('a', dueAt: DateTime.utc(2026, 10, 1)),
        mission('b', dueAt: DateTime.utc(2026, 10, 8)),
        mission('c'),
      ];
      expect(CourseItinerary.datedStop(later, now), 1);
      expect(open(groups: later, trip: trip), {'a', 'b'});
    });

    test('a completed later city stays open', () {
      expect(open(groups: groups, trip: trip, completed: {'d'}), {
        'a',
        'b',
        'd',
      });
    });
  });

  group('the class location', () {
    final groups = [mission('a'), mission('b'), mission('c')];
    CourseMissionsEvent copyOf(List<String> ids) => CourseMissionsEvent(
      version: CourseMissionsEvent.tripVersion,
      revision: 1,
      missions: [
        for (final id in ids) CourseMission(loId: id, activityIds: const []),
      ],
    );
    final copy = copyOf(['a', 'b', 'c']);

    test('an undated trip marks the ship\'s stop', () {
      expect(
        CourseItinerary.classStop(
          groups: groups,
          trip: const CourseTrip(),
          position: const CoursePositionEvent(stop: 2, fromStop: 0, since: 1),
          copy: copy,
          now: now,
        ),
        2,
      );
      expect(
        CourseItinerary.classStop(
          groups: groups,
          trip: const CourseTrip(),
          position: null,
          copy: copy,
          now: now,
        ),
        isNull,
      );
      // A stop beyond the list (a shorter copy since) marks nothing.
      expect(
        CourseItinerary.classStop(
          groups: groups,
          trip: const CourseTrip(),
          position: const CoursePositionEvent(stop: 9, fromStop: 0, since: 1),
          copy: copy,
          now: now,
        ),
        isNull,
      );
    });

    test('the ship\'s stop is placed by its Mission, not its index', () {
      // The record lists an empty Can-Do ('x') the course page leaves out,
      // so the record's stop 2 ('b') is the page's second Mission.
      expect(
        CourseItinerary.classStop(
          groups: [mission('a'), mission('b')],
          trip: const CourseTrip(),
          position: const CoursePositionEvent(stop: 2, fromStop: 0, since: 1),
          copy: copyOf(['a', 'x', 'b']),
          now: now,
        ),
        1,
      );
      // The ship at a Mission the page does not show marks nothing.
      expect(
        CourseItinerary.classStop(
          groups: [mission('a'), mission('b')],
          trip: const CourseTrip(),
          position: const CoursePositionEvent(stop: 1, fromStop: 0, since: 1),
          copy: copyOf(['a', 'x', 'b']),
          now: now,
        ),
        isNull,
      );
    });

    test(
      'a dated trip, and a course that is not a trip, mark by the dates',
      () {
        final dated = [
          mission('a', dueAt: DateTime.utc(2026, 11, 1)),
          mission('b', dueAt: DateTime.utc(2026, 11, 20)),
        ];
        expect(
          CourseItinerary.classStop(
            groups: dated,
            trip: CourseTrip(startDate: DateTime.utc(2026, 10, 1)),
            position: null,
            copy: null,
            now: now,
          ),
          1,
        );
        expect(
          CourseItinerary.classStop(
            groups: dated,
            trip: null,
            position: null,
            copy: null,
            now: now,
          ),
          1,
        );
      },
    );
  });

  group('the position and access records', () {
    test('a position is three non-negative integers', () {
      expect(
        CoursePositionEvent.tryParse({
          'stop': 1,
          'from_stop': 0,
          'since': 5,
        })?.stop,
        1,
      );
      expect(
        CoursePositionEvent.tryParse({'stop': '1', 'from_stop': 0, 'since': 5}),
        isNull,
      );
      expect(
        CoursePositionEvent.tryParse({'stop': -1, 'from_stop': 0, 'since': 5}),
        isNull,
      );
      expect(CoursePositionEvent.tryParse('x'), isNull);
    });

    test('an access record lists Mission ids', () {
      expect(
        CourseAccessEvent.tryParse({
          'open': ['a', 'b'],
        })?.openMissionIds,
        {'a', 'b'},
      );
      expect(
        CourseAccessEvent.tryParse({
          'open': ['a', 2],
        }),
        isNull,
      );
      expect(CourseAccessEvent.tryParse({}), isNull);
    });
  });
}
