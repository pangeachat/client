import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/central_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

class PickCefrLevelOnboardingStep extends OnboardingStep {
  PickCefrLevelOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  @override
  bool get enableGoForward => state.languageLevel != null;

  void selectCefrLevel(LanguageLevelTypeEnum? level) =>
      state.setLanguageLevel(level);

  @override
  Future<OnboardingStep?> execute() async {
    final level = state.languageLevel;
    final type = state.userType;

    if (level == null || type == null) {
      throw StateError("Pick cefr level step is not fully set up");
    }

    await state.accountUpdater.updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(cefrLevel: level),
      );
    });

    // A joined course ends onboarding on the joined-course page, and for a
    // teacher it takes the place of the course request — they already have a
    // course. See joining-courses.instructions.md.
    if (state.joinedRoomId != null) {
      return JoinedCourseOnboardingStep.next(client: client, state: state);
    }

    if (type == UserType.student) {
      final central = await _centralCourseStep();
      if (central != null) return central;
    }

    return switch (type) {
      UserType.student =>
        state.trialInfoProvider.shouldShowTrialPage
            ? FreeTrialOnboardingStep(
                client: client,
                state: state,
                maxRemainingSteps: maxRemainingSteps,
              )
            : null,
      UserType.teacher => CustomCourseOnboardingStep(
        client: client,
        state: state,
        maxRemainingSteps: 0,
      ),
    };
  }

  /// A learner who didn't join with a class code is offered their language's
  /// central course next. With none, or a failed lookup, they get a course of
  /// their own with no plan, which a later app open repairs; it has nothing
  /// to show yet, so onboarding still ends on the map. See
  /// joining-courses.instructions.md § The central course.
  Future<OnboardingStep?> _centralCourseStep() async {
    final language = state.targetLanguage?.langCodeShort;
    if (language == null) return null;
    final central = await state.courseProvider.centralCourseFor(language);
    if (central != null) {
      return CentralCourseOnboardingStep(
        client: client,
        state: state,
        central: central,
        plan: await state.courseProvider.getCourse(central.courseId),
        language: language,
        maxRemainingSteps: state.trialInfoProvider.shouldShowTrialPage ? 1 : 0,
      );
    }
    if (state.ownCourseRoomId != null) return null;
    try {
      state.setOwnCourseRoomId(
        await state.courseProvider.createOwnCourse(language: language),
      );
    } catch (e, s) {
      // Onboarding goes on; the app-open check makes the course instead.
      ErrorHandler.logError(e: e, s: s, data: {'target_language': language});
    }
    return null;
  }

  @override
  OnboardingStep? skip() => null;
}
