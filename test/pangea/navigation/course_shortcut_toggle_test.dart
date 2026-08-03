import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/widgets/layouts/workspace_shell.dart';

/// Regression coverage for #8098: with NO joined courses the narrow rail's 4th
/// slot is the `+` add-course button, whose own surface is the add-course hub —
/// the same surface the Courses rail item opens. The shell was only ever
/// reporting `courseShortcutHostsCavity` for a joined COURSE sheet, so with the
/// hub already up the `+` tap fell through to `setSection(addcourse)`: a
/// same-URL navigation, i.e. a silent no-op. The button neither opened nor
/// closed the hub, while the Courses item beside it toggled fine.
///
/// Drives the production predicate ([courseShortcutHostsCavity] in
/// `workspace_shell.dart`) directly — the widget's toggle behaviour once the
/// flag is set is pinned in `mobile_nav_widget_test.dart`.
void main() {
  const courseA = '!course-a:example.org';
  const courseB = '!course-b:example.org';

  group('no joined courses — the shortcut IS the add-course button', () {
    test('the hub cavity is the shortcut\'s own surface (#8098)', () {
      expect(
        courseShortcutHostsCavity(
          cavityToken: const AddCoursePanelToken(),
          shortcutCourseId: null,
          activeSpaceId: null,
        ),
        isTrue,
      );
    });

    test('an add-course SUBPAGE cavity is the shortcut\'s surface too', () {
      // Browse / start-my-own / enter-a-code are the same rail item's family
      // (`cavitySection` reports Courses for them), so the shortcut toggles
      // them exactly as the Courses item does — the two must not disagree.
      expect(
        courseShortcutHostsCavity(
          cavityToken: const AddCoursePagePanelToken(
            AddCoursePageTokenParam(subpage: AddCourseSubpageEnum.browse),
          ),
          shortcutCourseId: null,
          activeSpaceId: null,
        ),
        isTrue,
      );
    });

    test('another section cavity navigates instead of toggling', () {
      expect(
        courseShortcutHostsCavity(
          cavityToken: const ChatsPanelToken(),
          shortcutCourseId: null,
          activeSpaceId: null,
        ),
        isFalse,
      );
    });

    test('a bare map (no cavity) navigates', () {
      expect(
        courseShortcutHostsCavity(
          cavityToken: null,
          shortcutCourseId: null,
          activeSpaceId: null,
        ),
        isFalse,
      );
    });
  });

  group('a joined course fills the slot (#7537, unchanged)', () {
    test('its own course sheet toggles', () {
      expect(
        courseShortcutHostsCavity(
          cavityToken: const CoursePanelToken(),
          shortcutCourseId: courseA,
          activeSpaceId: courseA,
        ),
        isTrue,
      );
    });

    test('a DIFFERENT course sheet navigates', () {
      expect(
        courseShortcutHostsCavity(
          cavityToken: const CoursePanelToken(),
          shortcutCourseId: courseA,
          activeSpaceId: courseB,
        ),
        isFalse,
      );
    });

    test('the add-course hub navigates — the hub is not this course', () {
      expect(
        courseShortcutHostsCavity(
          cavityToken: const AddCoursePanelToken(),
          shortcutCourseId: courseA,
          activeSpaceId: courseA,
        ),
        isFalse,
      );
    });

    test('a live room over the course context navigates', () {
      expect(
        courseShortcutHostsCavity(
          cavityToken: const RoomPanelToken(RoomTokenParam(id: '!room:x.org')),
          shortcutCourseId: courseA,
          activeSpaceId: courseA,
        ),
        isFalse,
      );
    });
  });
}
