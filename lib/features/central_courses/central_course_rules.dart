import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

/// Who is offered their language's central course, and how a learner's own
/// course waits for a plan. See joining-courses.instructions.md § The central
/// course.
abstract class CentralCourseRules {
  static bool qualifies({
    required UserType? role,
    required String? language,
    required bool inAnyCourse,
  }) => role != UserType.teacher && language != null && !inAnyCourse;

  /// The plan event of a learner's own course made with no plan: it names
  /// the language, so a later app open knows which central course's plan to
  /// add, and carries no plan id, so it reads as no course until then.
  static Map<String, Object?> pendingPlan(String language) => {'l2': language};

  /// The language a learner's own course is waiting for a plan in, or null
  /// when [planContent] already names a plan or names no language.
  static String? awaitingPlanLanguage(Map<String, Object?>? planContent) {
    if (planContent == null) return null;
    final planId = planContent['uuid'] ?? planContent['course_plan_id'];
    if (planId is String && planId.isNotEmpty) return null;
    final language = planContent['l2'];
    return language is String && language.isNotEmpty ? language : null;
  }
}
