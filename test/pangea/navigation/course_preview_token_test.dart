import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/pangea/spaces/course_access_filter.dart';

// The single-course PREVIEW state of the add-course flow (#7826) — the token
// predicate the shell keys the low sheet rest, the map's preview scope, and
// the camera padding on. See course-preview.instructions.md.
void main() {
  group('AddCoursePageTokenParam.isCoursePreview (#7826)', () {
    test('the browse list is not a preview; a tapped course is', () {
      const list = AddCoursePageTokenParam(
        subpage: AddCourseSubpageEnum.browse,
      );
      const preview = AddCoursePageTokenParam(
        subpage: AddCourseSubpageEnum.browse,
        previewRoomId: '!abc',
      );
      expect(list.isCoursePreview, isFalse);
      expect(preview.isCoursePreview, isTrue);
    });

    test(
      'the own list is not a preview; a selected plan is; the invite step is not',
      () {
        const list = AddCoursePageTokenParam(subpage: AddCourseSubpageEnum.own);
        const selected = AddCoursePageTokenParam(
          subpage: AddCourseSubpageEnum.own,
          createCourseId: 'plan-uuid',
        );
        const invite = AddCoursePageTokenParam(
          subpage: AddCourseSubpageEnum.own,
          createCourseId: 'plan-uuid',
          showNewCourseInvitePage: true,
        );
        expect(list.isCoursePreview, isFalse);
        expect(selected.isCoursePreview, isTrue);
        expect(invite.isCoursePreview, isFalse);
      },
    );

    test('the enter-a-code page is never a preview', () {
      const code = AddCoursePageTokenParam(
        subpage: AddCourseSubpageEnum.private,
        privateCourseJoinCode: 'vj3pc8b',
      );
      expect(code.isCoursePreview, isFalse);
    });

    test('preview state survives the URL round-trip', () {
      const browse = AddCoursePageTokenParam(
        subpage: AddCourseSubpageEnum.browse,
        previewRoomId: '!room',
      );
      expect(
        AddCoursePageTokenParam.parse(browse.build()).isCoursePreview,
        isTrue,
      );

      const own = AddCoursePageTokenParam(
        subpage: AddCourseSubpageEnum.own,
        createCourseId: 'plan-uuid',
      );
      expect(
        AddCoursePageTokenParam.parse(own.build()).isCoursePreview,
        isTrue,
      );
    });
  });

  // The browse list's access pill rides the token like the language filter,
  // so it survives opening a preview and coming back (#9358).
  group('AddCoursePageTokenParam.accessFilter (#9358)', () {
    test('round-trips the URL, with and without a preview', () {
      for (final filter in CourseAccessFilter.values) {
        for (final previewRoomId in [null, '!room']) {
          final param = AddCoursePageTokenParam(
            subpage: AddCourseSubpageEnum.browse,
            initialLanguageFilter: 'es',
            previewRoomId: previewRoomId,
            accessFilter: filter,
          );
          expect(AddCoursePageTokenParam.parse(param.build()), param);
        }
      }
    });

    test('the default leaves the URL unchanged', () {
      const param = AddCoursePageTokenParam(
        subpage: AddCourseSubpageEnum.browse,
        initialLanguageFilter: 'es',
      );
      expect(param.build(), 'browse.les');
    });

    test('an unknown filter name opens the list unfiltered', () {
      expect(
        AddCoursePageTokenParam.parse('browse.les.rbogus').accessFilter,
        CourseAccessFilter.all,
      );
    });

    test('backing out of a preview keeps the filter', () {
      const preview = AddCoursePageTokenParam(
        subpage: AddCourseSubpageEnum.browse,
        previewRoomId: '!room',
        accessFilter: CourseAccessFilter.public,
      );
      expect(preview.poppedParam?.accessFilter, CourseAccessFilter.public);
    });

    test('the preview back button carries it from the open panel', () {
      final previewUrl = WorkspaceNav.openAddCoursePage(
        Uri.parse('/'),
        AddCourseSubpageEnum.browse,
        previewRoomId: '!room',
        accessFilter: CourseAccessFilter.restricted,
      );
      final backUrl = WorkspaceNav.openAddCoursePage(
        Uri.parse(previewUrl),
        AddCourseSubpageEnum.browse,
      );
      final list = parseOpenPanels(
        Uri.parse(backUrl),
      ).left.whereType<AddCoursePagePanelToken>().single.param!;
      expect(list.previewRoomId, isNull);
      expect(list.accessFilter, CourseAccessFilter.restricted);
    });
  });
}
