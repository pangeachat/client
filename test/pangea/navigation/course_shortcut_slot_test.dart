import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/layouts/workspace_shell.dart';

/// The narrow rail's course-shortcut slot (#8599): which course the 4th rail
/// item shows once the remembered one is gone. See "Single-column bottom nav"
/// in routing.instructions.md.
void main() {
  setUp(courseShortcutHistory.clear);

  test(
    'no joined course leaves the slot empty (the `+` add-course button)',
    () {
      courseShortcutHistory.add('!a');
      expect(courseShortcutIdFor([]), isNull);
    },
  );

  test('the single joined course wins, whatever the history says', () {
    courseShortcutHistory.add('!gone');
    expect(courseShortcutIdFor(['!a']), '!a');
  });

  test('the most-recently-opened joined course wins over the client order', () {
    courseShortcutHistory.addAll(['!c', '!a']);
    expect(courseShortcutIdFor(['!a', '!b', '!c']), '!c');
  });

  test('deleting the course in the slot falls back to the one opened before '
      'it, not to an arbitrary other course', () {
    // Opened !a, then !c; !c is then deleted and drops out of the joined list.
    courseShortcutHistory.addAll(['!c', '!a']);
    expect(courseShortcutIdFor(['!b', '!a']), '!a');
  });

  test('with nothing in history still joined, the client order decides', () {
    courseShortcutHistory.addAll(['!gone', '!alsogone']);
    expect(courseShortcutIdFor(['!b', '!a']), '!b');
  });
}
