import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';
import 'package:fluffychat/pangea/user/user_model.dart';

class PickCefrLevelOnboardingStep extends OnboardingStep {
  final UserType type;
  final LanguageModel baseLanguage;
  final LanguageModel targetLanguage;

  PickCefrLevelOnboardingStep({
    required super.client,
    super.stepIndex = 5,
    required super.totalSteps,
    required super.prevStep,
    required this.type,
    required this.baseLanguage,
    required this.targetLanguage,
  });

  LanguageLevelTypeEnum? _level;

  Future<void> Function(Profile Function(Profile))? updateProfile;
  void setup(Future<void> Function(Profile Function(Profile)) updateProfile) {
    this.updateProfile = updateProfile;
  }

  LanguageLevelTypeEnum? get level => _level;

  @override
  bool get enableGoForward => _level != null;

  void selectCefrLevel(LanguageLevelTypeEnum? level) => _level = level;

  @override
  Future<OnboardingStep?> execute() async {
    final updateProfile = this.updateProfile;
    if (updateProfile == null) {
      throw StateError("Pick CEFR level step is not fully set up");
    }

    final level = _level;
    if (level == null) {
      throw StateError("Cefr level is null");
    }

    await updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(cefrLevel: level),
      );
    });

    return switch (type) {
      UserType.student => null,
      UserType.teacher => CustomCourseOnboardingStep(
        prevStep: this,
        client: client,
        baseLanguage: baseLanguage,
        targetLanguage: targetLanguage,
        languageLevel: level,
      ),
    };
  }

  @override
  OnboardingStep? skip() => null;
}
