import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/central_courses/central_course_rules.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

/// Who is joined to their language's central course (#9591).
/// See joining-courses.instructions.md § The central course.
void main() {
  const me = '@learner:pangea.chat';
  const support = '@support:pangea.chat';
  const bot = '@bot:pangea.chat';

  group('CentralCourseRules.qualifies', () {
    bool qualifies({
      UserType? role = UserType.student,
      String? language = 'es',
      List<String> left = const [],
      bool inTeachersCourse = false,
    }) => CentralCourseRules.qualifies(
      role: role,
      language: language,
      leftLanguages: left,
      inTeachersCourse: inTeachersCourse,
    );

    test('a learner with no teacher\'s course is joined', () {
      expect(qualifies(), isTrue);
      expect(qualifies(role: null), isTrue);
    });

    test('an account that chose teacher is never joined', () {
      expect(qualifies(role: UserType.teacher), isFalse);
    });

    test('a learner in a teacher\'s course is not joined', () {
      expect(qualifies(inTeachersCourse: true), isFalse);
    });

    test(
      'a learner who left that language\'s central course is not joined',
      () {
        expect(qualifies(left: ['es']), isFalse);
        expect(qualifies(left: ['fr']), isTrue);
      },
    );

    test('an account with no target language is not joined', () {
      expect(qualifies(language: null), isFalse);
    });
  });

  group('CentralCourseRules.hasOtherHumanAdmin', () {
    bool other(Map<String, Object?> users) =>
        CentralCourseRules.hasOtherHumanAdmin(
          users,
          self: me,
          support: support,
          bot: bot,
        );

    test('a teacher admin makes it a teacher\'s course', () {
      expect(other({me: 0, '@teacher:pangea.chat': 100}), isTrue);
    });

    test('a course the learner made alone is not a teacher\'s course', () {
      expect(other({me: 100, bot: 100}), isFalse);
    });

    test('the central course itself is not a teacher\'s course', () {
      expect(other({support: 100, bot: 100, me: 0}), isFalse);
    });

    test('a moderator below admin does not count', () {
      expect(other({me: 100, '@mod:pangea.chat': 50}), isFalse);
    });
  });

  group('CentralCourseRules.isCentralMark', () {
    test('only the support account\'s mark counts, as in the catalog', () {
      expect(
        CentralCourseRules.isCentralMark({'central': true}, support, support),
        isTrue,
      );
      expect(
        CentralCourseRules.isCentralMark(
          {'central': true},
          '@someone:pangea.chat',
          support,
        ),
        isFalse,
      );
      expect(
        CentralCourseRules.isCentralMark({'central': false}, support, support),
        isFalse,
      );
      expect(CentralCourseRules.isCentralMark({}, support, support), isFalse);
    });

    test('support is the account of the learner\'s own homeserver', () {
      expect(
        CentralCourseRules.supportUserId('@learner:staging.pangea.chat'),
        '@support:staging.pangea.chat',
      );
    });
  });

  group('UserSettings.leftCentralCourses', () {
    test('a leave is saved per language and survives the round trip', () {
      final settings = UserSettings().withLeftCentralCourse('es');
      expect(settings.leftCentralCourses, ['es']);
      final read = UserSettings.fromJson(settings.toJson());
      expect(read.leftCentralCourses, ['es']);
      expect(read, settings);
    });

    test('leaving twice keeps one entry', () {
      final settings = UserSettings()
          .withLeftCentralCourse('es')
          .withLeftCentralCourse('es')
          .withLeftCentralCourse('fr');
      expect(settings.leftCentralCourses, ['es', 'fr']);
    });

    test('an account that never left writes nothing', () {
      expect(UserSettings().leftCentralCourses, isEmpty);
      expect(
        UserSettings().toJson().containsKey('left_central_courses'),
        isFalse,
      );
    });
  });
}
