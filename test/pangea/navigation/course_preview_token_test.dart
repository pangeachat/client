import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';

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
}
