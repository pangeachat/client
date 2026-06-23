import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

class UserTypeOnboardingStep extends OnboardingStep {
  UserTypeOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  void setUserType(UserType type) => state.setUserType(type);

  @override
  bool get enableGoForward => state.userType != null;

  Future<OnboardingStep?> _getNextStep() async {
    final type = state.userType;
    if (type == null) {
      throw StateError("Must set user type to move to next step");
    }

    final courseCode = state.courseProvider.getCachedJoinCode();
    if (courseCode != null) {
      try {
        final roomId = await state.courseProvider.joinSpaceWithCode(courseCode);
        final course = await state.courseProvider.getCourseByRoomId(roomId);

        state.setJoinedRoomId(roomId);
        state.setJoinedCoursePlan(course);

        final targetLangCode = course.targetLanguage;
        final baseLangCode = course.languageOfInstructions;
        final cefrLevel = course.cefrLevel;

        final targetLang = PLanguageStore.byLangCode(targetLangCode);
        final baseLang = PLanguageStore.byLangCode(baseLangCode);

        state.setTargetLanguage(targetLang);
        state.setBaseLanguage(baseLang);
        state.setLanguageLevel(cefrLevel);

        await state.accountUpdater.updateProfile((profile) {
          return profile.copyWith(
            userSettings: profile.userSettings.copyWith(
              targetLanguage: targetLangCode,
              sourceLanguage: baseLangCode,
              cefrLevel: cefrLevel,
            ),
          );
        });

        return JoinedCourseOnboardingStep(
          client: client,
          state: state,
          maxRemainingSteps: 0,
        );
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {'cached_course_id': courseCode},
        );
      }
    }

    final maxRemainingSteps = switch (state.userType) {
      UserType.student => 2,
      UserType.teacher => 3,
      null => 2,
    };

    return CourseCodeOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: maxRemainingSteps,
    );
  }

  @override
  Future<OnboardingStep?> execute() async => _getNextStep();

  @override
  OnboardingStep? skip() {
    throw StateError("Cannot skip user type onboarding step");
  }
}
