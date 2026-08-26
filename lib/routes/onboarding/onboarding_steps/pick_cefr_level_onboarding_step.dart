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
      return JoinedCourseOnboardingStep(
        client: client,
        state: state,
        maxRemainingSteps: 0,
      );
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

  @override
  OnboardingStep? skip() => null;
}
