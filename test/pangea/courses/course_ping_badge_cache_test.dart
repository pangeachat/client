import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';

void main() {
  const ping = (
    courseId: '!course:server',
    activityId: 'activity-1',
    sessionRoomId: '!session:server',
  );

  group('CoursePingBadgeCache', () {
    tearDown(() => CoursePingBadgeCache.instance.value = null);

    test('set stores the ping and notifies listeners', () {
      var notified = 0;
      CoursePingBadgeCache.instance.addListener(() => notified++);

      CoursePingBadgeCache.set(ping);

      expect(CoursePingBadgeCache.instance.value?.activityId, 'activity-1');
      expect(notified, 1);
    });

    test('an unfollowed ping survives clearForCourse', () {
      CoursePingBadgeCache.set(ping);

      // A premature course-page remount (the ping already marked read) must
      // not wipe badges the learner hasn't acted on yet.
      CoursePingBadgeCache.clearForCourse('!course:server');
      expect(CoursePingBadgeCache.instance.value, isNotNull);
    });

    test('a followed ping clears, but only for the matching course', () {
      CoursePingBadgeCache.set(ping);
      CoursePingBadgeCache.markFollowed('activity-1');

      CoursePingBadgeCache.clearForCourse('!other:server');
      expect(CoursePingBadgeCache.instance.value, isNotNull);

      CoursePingBadgeCache.clearForCourse('!course:server');
      expect(CoursePingBadgeCache.instance.value, isNull);
    });

    test('markFollowed ignores a non-matching activity', () {
      CoursePingBadgeCache.set(ping);
      CoursePingBadgeCache.markFollowed('activity-other');

      CoursePingBadgeCache.clearForCourse('!course:server');
      expect(CoursePingBadgeCache.instance.value, isNotNull);
    });

    test('re-capturing the same unread ping keeps the followed flag', () {
      CoursePingBadgeCache.set(ping);
      CoursePingBadgeCache.markFollowed('activity-1');

      // A second mount racing the read marker re-captures the same ping.
      CoursePingBadgeCache.set(ping);

      CoursePingBadgeCache.clearForCourse('!course:server');
      expect(CoursePingBadgeCache.instance.value, isNull);
    });

    test('a NEW ping resets the followed flag', () {
      CoursePingBadgeCache.set(ping);
      CoursePingBadgeCache.markFollowed('activity-1');

      CoursePingBadgeCache.set((
        courseId: '!course:server',
        activityId: 'activity-2',
        sessionRoomId: '!session2:server',
      ));

      CoursePingBadgeCache.clearForCourse('!course:server');
      expect(CoursePingBadgeCache.instance.value, isNotNull);
    });
  });
}
