import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PickCefrLevelOnboardingStep extends OnboardingStep {
  final UserType type;

  PickCefrLevelOnboardingStep({
    required super.client,
    super.stepIndex = 5,
    required super.totalSteps,
    required super.prevStep,
    required this.type,
  });

  LanguageLevelTypeEnum? _level;
  LanguageLevelTypeEnum? get level => _level;

  @override
  bool get enableGoForward => _level != null;

  @override
  OnboardingStep? get nextStep {
    if (_level == null) {
      throw StateError("Cannot go to next step without CEFR level");
    }

    return switch (type) {
      UserType.student => null,
      UserType.teacher => CustomCourseOnboardingStep(
        prevStep: this,
        client: client,
      ),
    };
  }

  void selectCefrLevel(LanguageLevelTypeEnum? level) => _level = level;

  @override
  Future<void> execute() async {
    await MatrixState.pangeaController.userController.updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(cefrLevel: _level),
      );
    }, waitForDataInSync: true);
  }
}
