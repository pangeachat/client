import 'package:fluffychat/routes/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
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

    return switch (type) {
      UserType.student => null,
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
