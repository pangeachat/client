import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';

void main() {
  group('CoursePingBadgeCache', () {
    tearDown(() => CoursePingBadgeCache.instance.value = null);

    test('set stores the ping and notifies listeners', () {
      var notified = 0;
      CoursePingBadgeCache.instance.addListener(() => notified++);

      CoursePingBadgeCache.set((
        courseId: '!course:server',
        activityId: 'activity-1',
        sessionRoomId: '!session:server',
      ));

      expect(CoursePingBadgeCache.instance.value?.activityId, 'activity-1');
      expect(notified, 1);
    });

    test('clearForCourse clears only the matching course', () {
      CoursePingBadgeCache.set((
        courseId: '!course:server',
        activityId: 'activity-1',
        sessionRoomId: '!session:server',
      ));

      // A visit to a DIFFERENT course must not wipe this course's ping.
      CoursePingBadgeCache.clearForCourse('!other:server');
      expect(CoursePingBadgeCache.instance.value, isNotNull);

      CoursePingBadgeCache.clearForCourse('!course:server');
      expect(CoursePingBadgeCache.instance.value, isNull);
    });
  });
}
