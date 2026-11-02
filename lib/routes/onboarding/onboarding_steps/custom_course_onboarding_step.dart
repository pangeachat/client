import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';

class CustomCourseOnboardingStep extends OnboardingStep {
  CustomCourseOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  // Kept in the onboarding state, like every other page's choices, so going
  // back and forward again keeps what was typed.
  void setName(String name) => state.setCourseRequestName(name);
  void setInstitution(String institution) =>
      state.setCourseRequestInstitution(institution);
  void setGoals(String goals) => state.setCourseRequestGoals(goals);

  @override
  bool get enableGoForward =>
      state.courseRequestName?.isNotEmpty == true &&
      state.courseRequestInstitution?.isNotEmpty == true &&
      state.courseRequestGoals?.isNotEmpty == true;

  @override
  Future<OnboardingStep?> execute() async {
    final baseLanguage = state.baseLanguage;
    final targetLanguage = state.targetLanguage;
    final languageLevel = state.languageLevel;

    if (targetLanguage == null ||
        baseLanguage == null ||
        languageLevel == null) {
      throw StateError("Custom course onboarding step is not fully set up");
    }

    final name = state.courseRequestName;
    final institution = state.courseRequestInstitution;
    final goals = state.courseRequestGoals;
    if (name == null || institution == null || goals == null) {
      throw StateError(
        "Cannot request custom course without name, institution, and goals",
      );
    }

    final languagePair =
        "${baseLanguage.displayName} -> ${targetLanguage.displayName}";

    final request = CustomCourseRequestModel(
      name: name,
      languagePair: languagePair,
      languageLevel: languageLevel,
      institution: institution,
      goals: goals,
    );

    // Moving forward again with nothing changed doesn't send a second request.
    if (request.storageKey != state.sentCourseRequestKey) {
      final resp = await state.courseProvider.requestCustomCourse(request);
      if (resp.isError) {
        throw resp.asError!;
      }
      state.setSentCourseRequestKey(request.storageKey);
    }

    if (state.trialInfoProvider.shouldShowTrialPage) {
      return FreeTrialOnboardingStep(
        client: client,
        state: state,
        maxRemainingSteps: maxRemainingSteps,
      );
    }

    return null;
  }

  @override
  OnboardingStep? skip() => null;
}
