import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';

/// What onboarding does once the user is a member of a course, shared by the
/// two steps that can join one: the user-type step joins with a code ferried
/// from a class link, the course-code step with a code the user typed.
///
/// Joining and loading the course's quest are separate outcomes — a space can
/// be joined while its quest does not resolve — so a join is never presented
/// as no join. Onboarding asks the user for whatever the quest could not
/// supply and finishes on the joined-course page either way. See
/// `joining-courses.instructions.md`.
mixin CourseJoinStep on OnboardingStep {
  Future<OnboardingStep> stepAfterJoin(String roomId) async {
    state.setJoinedRoomId(roomId);
    final course = await state.courseProvider.getCourseByRoomId(roomId);
    return course != null ? _stepAfterQuest(course) : _stepAfterSpace(roomId);
  }

  /// Whether the course's own target language can be recorded without asking:
  /// the space records one, onboarding has a base language to pair it with,
  /// and the two differ — a course cannot be taught in the language it teaches.
  static bool canUseCourseLanguage(
    LanguageModel? courseLanguage,
    LanguageModel? baseLanguage,
  ) =>
      courseLanguage != null &&
      baseLanguage != null &&
      courseLanguage.langCodeShort != baseLanguage.langCodeShort;

  /// The base language recorded when onboarding does not ask for one — the
  /// same default the language step offers.
  LanguageModel? get _deviceLanguage =>
      LanguageService.systemLanguage ??
      PLanguageStore.byLangCode(LanguageKeys.defaultLanguage);

  /// The quest resolved, so it supplies both languages and the level and there
  /// is nothing left to ask.
  Future<OnboardingStep> _stepAfterQuest(CoursePlanModel course) async {
    state.setJoinedCoursePlan(course);
    state.setTargetLanguage(PLanguageStore.byLangCode(course.targetLanguage));
    state.setBaseLanguage(
      PLanguageStore.byLangCode(course.languageOfInstructions),
    );
    state.setLanguageLevel(course.cefrLevel);

    await state.accountUpdater.updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: course.targetLanguage,
          sourceLanguage: course.languageOfInstructions,
          cefrLevel: course.cefrLevel,
        ),
      );
    });

    return JoinedCourseOnboardingStep.next(client: client, state: state);
  }

  /// The quest did not resolve, so the space is all onboarding has. It records
  /// its own target language next to the quest id, which pairs with the user's
  /// device language to leave only the level to ask for; without a usable one,
  /// the language step is shown.
  Future<OnboardingStep> _stepAfterSpace(String roomId) async {
    final baseLanguage = _deviceLanguage;
    final courseLanguage = PLanguageStore.byLangCode(
      client.getRoomById(roomId)?.coursePlan?.l2 ??
          LanguageKeys.unknownLanguage,
    );

    if (!canUseCourseLanguage(courseLanguage, baseLanguage)) {
      return PickLanguageOnboardingStep(
        client: client,
        state: state,
        maxRemainingSteps: 2,
      );
    }

    state.setTargetLanguage(courseLanguage);
    state.setBaseLanguage(baseLanguage);

    await state.accountUpdater.updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: courseLanguage!.langCode,
          sourceLanguage: baseLanguage!.langCode,
        ),
      );
    });

    return PickCefrLevelOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: 1,
    );
  }
}
