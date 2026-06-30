import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/courses/find_course_page.dart';

/// Covers #7230: the browse-public language filter must keep the language the
/// learner picked this session. Tapping a course opens the route-driven preview
/// (`/courses/preview/:courseroomid`); backing out remounts FindCoursePage, and
/// without the session memory `initState` reset the filter to the L2 default.
void main() {
  final fr = LanguageModel(langCode: 'fr', displayName: 'French');
  final es = LanguageModel(langCode: 'es', displayName: 'Spanish');

  group('FindCoursePageState.seedLanguage', () {
    test('the session memory wins over the L2 default (the fix)', () {
      expect(
        FindCoursePageState.seedLanguage(lastChosen: fr, l2Default: es),
        fr,
      );
    });

    test('falls back to the L2 default when nothing is remembered', () {
      expect(
        FindCoursePageState.seedLanguage(lastChosen: null, l2Default: es),
        es,
      );
    });

    test('a null L2 default with no memory yields null (no crash)', () {
      expect(
        FindCoursePageState.seedLanguage(lastChosen: null, l2Default: null),
        isNull,
      );
    });
  });
}
