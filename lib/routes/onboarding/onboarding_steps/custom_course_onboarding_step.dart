import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';

class CustomCourseOnboardingStep extends OnboardingStep {
  CustomCourseOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  String? _name;
  String? _institution;
  String? _goals;

  void setName(String name) => _name = name;
  void setInstitution(String institution) => _institution = institution;
  void setGoals(String goals) => _goals = goals;

  @override
  bool get enableGoForward =>
      _name?.isNotEmpty == true &&
      _institution?.isNotEmpty == true &&
      _goals?.isNotEmpty == true;

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

    final name = _name;
    final institution = _institution;
    final goals = _goals;
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

    final resp = await state.courseProvider.requestCustomCourse(request);
    if (resp.isError) {
      throw resp.asError!;
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
