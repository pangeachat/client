import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/features/languages/language_model.dart';

/// Covers #7269: returning to "Start my own" must keep the language the learner
/// picked this session (the back-arrow drops the URL `?lang=`), while a real
/// `?lang=` deep link still wins and the L2 default is the last resort.
void main() {
  final fr = LanguageModel(langCode: 'fr', displayName: 'French');
  final de = LanguageModel(langCode: 'de', displayName: 'German');
  final es = LanguageModel(langCode: 'es', displayName: 'Spanish');

  group('NewCoursePageState.seedLanguage', () {
    test('a ?lang= deep link wins over everything', () {
      expect(
        NewCoursePageState.seedLanguage(
          fromInitialCode: fr,
          lastChosen: de,
          userL2: es,
        ),
        fr,
      );
    });

    test('the session memory wins over the L2 default (the fix)', () {
      expect(
        NewCoursePageState.seedLanguage(
          fromInitialCode: null,
          lastChosen: fr,
          userL2: es,
        ),
        fr,
      );
    });

    test('falls back to the L2 default when nothing is remembered', () {
      expect(
        NewCoursePageState.seedLanguage(
          fromInitialCode: null,
          lastChosen: null,
          userL2: es,
        ),
        es,
      );
    });
  });
}
