import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_mismatch_popup.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';

class PickLanguageOnboardingStep extends OnboardingStep {
  PickLanguageOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  @override
  bool get enableGoForward {
    final base = state.baseLanguage;
    final target = state.targetLanguage;
    if (base == null || target == null) return false;
    return true;
  }

  void selectBaseLanguage(LanguageModel? lang) => state.setBaseLanguage(lang);

  void selectTargetLanguage(LanguageModel? lang) =>
      state.setTargetLanguage(lang);

  @override
  String nextStepText(L10n l10n) {
    final target = state.targetLanguage;
    if (target == null) return l10n.next;
    return l10n.continueWithLang(target.getDisplayName(l10n));
  }

  @override
  Future<OnboardingStep?> execute() async {
    final target = state.targetLanguage;
    final base = state.baseLanguage;

    if (target == null || base == null) {
      throw StateError("Target language or base language is null");
    }

    if (base.langCodeShort == target.langCodeShort) {
      throw IdenticalLanguageException();
    }

    await state.accountUpdater.updateProfile((profile) {
      return profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          targetLanguage: target.langCode,
          sourceLanguage: base.langCode,
        ),
      );
    });

    final maxRemainingSteps = switch (state.userType) {
      UserType.student => 0,
      UserType.teacher => 1,
      null => 0,
    };

    return PickCefrLevelOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: maxRemainingSteps,
    );
  }

  @override
  OnboardingStep? skip() {
    throw StateError("Cannot skip language selection onboarding step");
  }
}
