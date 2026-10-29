import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/central_courses/central_course_rules.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

/// Who is offered their language's central course, and how a learner's own
/// course waits for a plan. See joining-courses.instructions.md § The central
/// course.
void main() {
  group('CentralCourseRules.qualifies', () {
    bool qualifies({
      UserType? role = UserType.student,
      String? language = 'es',
      bool inAnyCourse = false,
    }) => CentralCourseRules.qualifies(
      role: role,
      language: language,
      inAnyCourse: inAnyCourse,
    );

    test('a learner in no course is asked', () {
      expect(qualifies(), isTrue);
      expect(qualifies(role: null), isTrue);
    });

    test('an account that chose teacher is never asked', () {
      expect(qualifies(role: UserType.teacher), isFalse);
    });

    test('a learner in any course is not asked', () {
      expect(qualifies(inAnyCourse: true), isFalse);
    });

    test('an account with no target language is not asked', () {
      expect(qualifies(language: null), isFalse);
    });
  });

  group('a learner\'s own course waiting for a plan', () {
    test('names its language, and the regular reader sees no course', () {
      final content = CentralCourseRules.pendingPlan('es');
      expect(CentralCourseRules.awaitingPlanLanguage(content), 'es');
      expect(CoursePlanEvent.tryParse(content), isNull);
    });

    test('a course with a plan is not waiting', () {
      expect(
        CentralCourseRules.awaitingPlanLanguage(
          CoursePlanEvent(uuid: 'quest-1', l2: 'es').toJson(),
        ),
        isNull,
      );
    });

    test('a removed plan, with no language, is not waiting', () {
      expect(CentralCourseRules.awaitingPlanLanguage({'uuid': ''}), isNull);
      expect(CentralCourseRules.awaitingPlanLanguage({}), isNull);
      expect(CentralCourseRules.awaitingPlanLanguage(null), isNull);
    });
  });
}
