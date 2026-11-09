import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'course_missions_fixtures.dart';

/// The v2 additions to the course record (`pangea.course_missions`, still
/// version 1): per-Can-Do `removed_activity_ids` and top-level
/// `removed_missions`. They parse strictly, survive a round trip, and are
/// absent from a record that has none — so a v1 record is byte-identical.
void main() {
  Map<String, dynamic> record({
    Object? removedActivityIds,
    Object? removedMissions,
  }) => {
    'version': 1,
    'revision': 2,
    'missions': [
      {
        'lo_id': 'lo1',
        'activity_ids': ['a1'],
        'removed_activity_ids': ?removedActivityIds,
      },
    ],
    'removed_missions': ?removedMissions,
  };

  group('removed_activity_ids', () {
    test('reads the hidden ids of a Can-Do', () {
      final copy = CourseMissionsEvent.tryParse(
        record(removedActivityIds: ['a2', 'a3']),
      )!;
      expect(copy.missions.single.removedActivityIds, ['a2', 'a3']);
      expect(copy.missions.single.activityIds, ['a1']);
    });

    test('is empty when the record has none', () {
      final copy = CourseMissionsEvent.tryParse(record())!;
      expect(copy.missions.single.removedActivityIds, isEmpty);
    });

    test('rejects a non-list or a non-string id', () {
      expect(
        CourseMissionsEvent.tryParse(record(removedActivityIds: 'a2')),
        isNull,
      );
      expect(
        CourseMissionsEvent.tryParse(record(removedActivityIds: ['a2', 7])),
        isNull,
      );
    });
  });

  group('removed_missions', () {
    Map<String, dynamic> removed({Object? shown = 1}) => {
      'lo_id': 'lo9',
      'activity_ids': ['x1', 'x2'],
      'shown_count': shown,
    };

    test('reads a removed Can-Do with the count that were shown', () {
      final copy = CourseMissionsEvent.tryParse(
        record(removedMissions: [removed()]),
      )!;
      final gone = copy.removedMissions.single;
      expect(gone.loId, 'lo9');
      expect(gone.activityIds, ['x1', 'x2']);
      expect(gone.shownCount, 1);
      expect(copy.allLoIds, {'lo1', 'lo9'});
    });

    test('rejects a malformed entry', () {
      for (final bad in <Object?>[
        'nope',
        [removed(shown: -1)],
        [removed(shown: 3)], // more shown than activities
        [removed(shown: '1')],
        [
          {'lo_id': '', 'activity_ids': [], 'shown_count': 0},
        ],
        [
          {
            'lo_id': 'lo9',
            'activity_ids': [1],
            'shown_count': 0,
          },
        ],
        ['not a map'],
      ]) {
        expect(
          CourseMissionsEvent.tryParse(record(removedMissions: bad)),
          isNull,
          reason: '$bad',
        );
      }
    });
  });

  test('both fields round-trip through toJson', () {
    final copy = CourseMissionsEvent.tryParse(
      record(
        removedActivityIds: ['a2'],
        removedMissions: [
          {
            'lo_id': 'lo9',
            'activity_ids': ['x1', 'x2'],
            'shown_count': 1,
          },
        ],
      ),
    )!;
    final again = CourseMissionsEvent.tryParse(copy.toJson())!;
    expect(again.toJson(), copy.toJson());
    expect(again.missions.single.removedActivityIds, ['a2']);
    expect(again.removedMissions.single.shownCount, 1);
  });

  test('a v1 record writes back without either field', () {
    final v1 = copyContent({
      'lo1': ['a1'],
    }, revision: 3);
    final json = CourseMissionsEvent.tryParse(v1)!.toJson();
    expect(json.containsKey('removed_missions'), isFalse);
    expect(
      (json['missions'] as List).single.containsKey('removed_activity_ids'),
      isFalse,
    );
  });
}
