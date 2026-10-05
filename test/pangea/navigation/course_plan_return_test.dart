import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/course_plan_return.dart';

void main() {
  group('CoursePlanReturn (back-arrow → full plan scroll hand-off, #9367)', () {
    tearDown(() => CoursePlanReturn.take(''));

    test('the matching course takes the activity exactly once', () {
      CoursePlanReturn.arm(courseId: '!s', activityId: 'act-1');
      expect(CoursePlanReturn.take('!s'), 'act-1');
      expect(CoursePlanReturn.take('!s'), isNull);
    });

    test('another course never takes it, and the miss clears it', () {
      CoursePlanReturn.arm(courseId: '!s', activityId: 'act-1');
      expect(CoursePlanReturn.take('!other'), isNull);
      expect(CoursePlanReturn.take('!s'), isNull);
    });
  });
}
