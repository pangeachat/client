import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_mismatch_popup.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PickLanguageOnboardingStep extends OnboardingStep {
  final UserType type;

  PickLanguageOnboardingStep({
    required super.client,
    super.stepIndex = 4,
    required super.totalSteps,
    required super.prevStep,
    required this.type,
  });

  LanguageModel? _baseLanguage;
  LanguageModel? _targetLanguage;

  LanguageModel? get baseLanguage => _baseLanguage;
  LanguageModel? get targetLanguage => _targetLanguage;

  @override
  bool get enableGoForward {
    final base = _baseLanguage;
    final target = _targetLanguage;
    if (base == null || target == null) return false;
    // if (base.langCodeShort == target.langCodeShort) return false;
    return true;
  }

  void selectBaseLanguage(LanguageModel? lang) => _baseLanguage = lang;

  void selectTargetLanguage(LanguageModel? lang) => _targetLanguage = lang;

  @override
  OnboardingStep? get nextStep {
    final base = _baseLanguage;
    final target = _targetLanguage;
    if (base == null || target == null) {
      throw StateError(
        "Cannot go to next step without base and target language set",
      );
    }

    if (base.langCodeShort == target.langCodeShort) {
      throw IdenticalLanguageException();
    }

    return PickCefrLevelOnboardingStep(
      prevStep: this,
      totalSteps: totalSteps,
      type: type,
      client: client,
    );
  }

  @override
  Future<void> execute() async {
    final target = _targetLanguage;
    final base = _baseLanguage;

    if (target == null || base == null) {
      throw StateError("Target language or base language is null");
    }

    if (base.langCodeShort == target.langCodeShort) {
      throw IdenticalLanguageException();
    }

    await MatrixState.pangeaController.userController.updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: target.langCode,
          sourceLanguage: base.langCode,
          // GABBY TODO set created at at right time: createdAt: DateTime.now(),
        ),
      );
    }, waitForDataInSync: true);
  }
}
