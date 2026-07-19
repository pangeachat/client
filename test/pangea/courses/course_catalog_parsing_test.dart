import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';

/// Parsing rules for the public course catalog.
///
/// Both parsers answer the same question — "is this a course?" — at the point
/// of reading, so a malformed record reads as "not a course" instead of
/// throwing out at a call site. See public-courses.instructions.md.
void main() {
  group('CoursePlanEvent.tryParse', () {
    test('reads the plan id from uuid', () {
      final event = CoursePlanEvent.tryParse({'uuid': 'quest-1'});
      expect(event?.uuid, 'quest-1');
    });

    test('falls back to course_plan_id, which server-created spaces write', () {
      final event = CoursePlanEvent.tryParse({'course_plan_id': 'quest-2'});
      expect(event?.uuid, 'quest-2');
    });

    test('prefers uuid when both keys are present', () {
      final event = CoursePlanEvent.tryParse({
        'uuid': 'quest-1',
        'course_plan_id': 'quest-2',
      });
      expect(event?.uuid, 'quest-1');
    });

    test('reads the target language', () {
      final event = CoursePlanEvent.tryParse({'uuid': 'q', 'l2': 'es'});
      expect(event?.l2, 'es');
    });

    test('a course with no recorded language parses, without one', () {
      final event = CoursePlanEvent.tryParse({'uuid': 'q'});
      expect(event, isNotNull);
      expect(event?.l2, isNull);
    });

    test('an event with no plan id is not a course', () {
      expect(CoursePlanEvent.tryParse({}), isNull);
      expect(CoursePlanEvent.tryParse({'l2': 'es'}), isNull);
    });

    test('a blanked plan id is not a course', () {
      // Matrix has no true state deletion, so removing a course plan means
      // blanking the event content.
      expect(CoursePlanEvent.tryParse({'uuid': ''}), isNull);
      expect(
        CoursePlanEvent.tryParse({'uuid': '', 'course_plan_id': ''}),
        isNull,
      );
    });

    test('a non-string plan id does not throw', () {
      expect(CoursePlanEvent.tryParse({'uuid': 42}), isNull);
    });

    test('round-trips through toJson, omitting an absent language', () {
      expect(CoursePlanEvent(uuid: 'q', l2: 'de').toJson(), {
        'uuid': 'q',
        'l2': 'de',
      });
      expect(CoursePlanEvent(uuid: 'q').toJson(), {'uuid': 'q'});
    });
  });

  group('PublicCoursesResponse.fromJson', () {
    Map<String, dynamic> room(String id, {String? courseId}) => {
      'room_id': id,
      'num_joined_members': 3,
      'world_readable': true,
      'guest_can_join': false,
      if (courseId != null) 'course_id': courseId,
    };

    test('parses entries that carry a course id', () {
      final resp = PublicCoursesResponse.fromJson({
        'chunk': [room('!a:server', courseId: 'quest-1')],
        'next_batch': '!a:server',
        'total_room_count_estimate': 1,
      });
      expect(resp.courses, hasLength(1));
      expect(resp.courses.single.courseId, 'quest-1');
    });

    test('drops an entry with no course id instead of failing the page', () {
      // A homeserver that predates the catalog eligibility rule can still send
      // one of these. Previously it threw and took the whole page down (#7542).
      final resp = PublicCoursesResponse.fromJson({
        'chunk': [
          room('!a:server', courseId: 'quest-1'),
          room('!b:server'),
          room('!c:server', courseId: 'quest-3'),
        ],
        'next_batch': '!c:server',
        'total_room_count_estimate': 3,
      });
      expect(resp.courses.map((c) => c.courseId), ['quest-1', 'quest-3']);
    });

    test('carries the pagination cursor through', () {
      final resp = PublicCoursesResponse.fromJson({
        'chunk': [room('!a:server', courseId: 'q')],
        'next_batch': '!a:server',
        'total_room_count_estimate': 9,
      });
      expect(resp.nextBatch, '!a:server');
      expect(resp.totalRoomCountEstimate, 9);
    });
  });
}
