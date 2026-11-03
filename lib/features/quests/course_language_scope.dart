import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Which courses and sessions count in the learner's current target language
/// (#9559). A learner's XP is kept per language, so progress is only shown
/// for content in the language they are learning now: a course or session in
/// another language would otherwise show its goals (read from room state)
/// with none of its XP (read for the current language only).
class CourseLanguageScope {
  const CourseLanguageScope._();

  /// Whether [course] is in the learner's current target language — the
  /// scope every Mission meter, the Learning Objectives list and the
  /// analytics bar's star count read. A course with no language recorded
  /// counts, as the star count and the leaderboard always have.
  static bool courseInTargetLanguage(Room? course) =>
      _inTargetLanguage(course?.coursePlan?.l2);

  /// Whether a live activity session is in the learner's current language:
  /// its activity's target language, short-code compared. A session whose
  /// plan hasn't loaded yet counts.
  static bool sessionInTargetLanguage(Room session) =>
      _inTargetLanguage(session.activityPlan?.req.targetLanguage);

  /// The saved sessions of the learner's current language: a save files the
  /// session in its activity's language's analytics room
  /// (`sendActivityAnalytics`), so this list is authoritative and needs no
  /// plan loaded. Read once per walk over the rooms. Empty with no target
  /// language (or before the controller is up), leaving each session to its
  /// plan's language.
  static Set<String> savedSessionIdsInTargetLanguage(Client client) {
    if (!MatrixState.isPangeaControllerInitialized) return const {};
    final userL2 = MatrixState.pangeaController.userController.userL2;
    if (userL2 == null) return const {};
    return client
            .ownAnalyticsRoomLocal(lang: userL2)
            ?.activityRoomIds
            .toSet() ??
        const {};
  }

  /// Whether a saved [session]'s XP counts in the learner's current
  /// language: it is filed under that language ([savedInLanguage], from
  /// [savedSessionIdsInTargetLanguage]), or — for a session saved before the
  /// filing existed — its loaded plan is in that language. A session in
  /// neither waits for its plan rather than adding another language's goals
  /// meanwhile.
  static bool savedSessionInTargetLanguage(
    Room session,
    Set<String> savedInLanguage,
  ) {
    if (savedInLanguage.contains(session.id)) return true;
    final planLanguage = session.activityPlan?.req.targetLanguage;
    return planLanguage != null && _inTargetLanguage(planLanguage);
  }

  /// [course]'s language, or null when none is recorded or the store doesn't
  /// know it.
  static LanguageModel? courseLanguage(Room? course) {
    final courseL2 = course?.coursePlan?.l2;
    return courseL2 == null ? null : PLanguageStore.byLangCode(courseL2);
  }

  /// [course]'s language as the learner reads it: its display name, else
  /// the recorded code.
  static String courseLanguageName(Room? course, L10n l10n) =>
      courseLanguage(course)?.getDisplayName(l10n) ??
      course?.coursePlan?.l2 ??
      '';

  /// [course]'s language when the learner could switch to it — not their
  /// current target and not their base language, the same rule the language
  /// chip uses (profile.instructions.md, "Switching from context"). Null
  /// when there is nothing to offer: the course is in their current
  /// language, in their base language (a switch there is refused), or has no
  /// language.
  static LanguageModel? courseSwitchLanguage(Room? course) {
    final language = courseLanguage(course);
    if (language == null || !MatrixState.isPangeaControllerInitialized) {
      return null;
    }
    final user = MatrixState.pangeaController.userController;
    return UserController.canSwitchTo(
          language,
          targetLangCode: user.userL2?.langCode,
          baseLangCode: user.userL1?.langCode,
        )
        ? language
        : null;
  }

  /// A content language [langCode] against the learner's target language,
  /// short-code compared. No code counts; with no target language set,
  /// nothing does.
  static bool _inTargetLanguage(String? langCode) {
    if (langCode == null) return true;
    if (!MatrixState.isPangeaControllerInitialized) return true;
    final userL2 = MatrixState.pangeaController.userController.userL2;
    if (userL2 == null) return false;
    return langCode.split('-').first == userL2.langCodeShort;
  }
}
