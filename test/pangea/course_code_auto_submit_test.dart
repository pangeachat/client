import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/courses/private/course_code_page.dart';

/// The one-shot auto-submit trigger for an inbound join code (#7524): the
/// join-with-code page fires exactly once per NEW code, whether the code
/// arrives at mount (initState, previous == null) or while already mounted
/// (didUpdateWidget — an in-app deep link changing only the token param).
/// The URL-consuming history REPLACE rebuilds the page with a null code, and
/// that transition must never re-fire.
void main() {
  group('CourseCodePage.shouldAutoSubmit', () {
    test('fires on a fresh mount with a code', () {
      expect(CourseCodePage.shouldAutoSubmit(null, 'vj3pc8b'), isTrue);
    });

    test('fires when a new code arrives while mounted', () {
      expect(CourseCodePage.shouldAutoSubmit(null, 'vj3pc8b'), isTrue);
      expect(CourseCodePage.shouldAutoSubmit('old1234', 'vj3pc8b'), isTrue);
    });

    test('does not fire when the consuming replace drops the code', () {
      expect(CourseCodePage.shouldAutoSubmit('vj3pc8b', null), isFalse);
    });

    test('does not fire on a rebuild carrying the same code', () {
      expect(CourseCodePage.shouldAutoSubmit('vj3pc8b', 'vj3pc8b'), isFalse);
      expect(CourseCodePage.shouldAutoSubmit(' vj3pc8b ', 'vj3pc8b'), isFalse);
    });

    test('does not fire without a code', () {
      expect(CourseCodePage.shouldAutoSubmit(null, null), isFalse);
      expect(CourseCodePage.shouldAutoSubmit(null, ''), isFalse);
      expect(CourseCodePage.shouldAutoSubmit(null, '   '), isFalse);
    });
  });
}
