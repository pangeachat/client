import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class CustomCourseOnboardingStep extends OnboardingStep {
  CustomCourseOnboardingStep({
    required super.client,
    super.stepIndex = 6,
    super.totalSteps = 6,
    required super.prevStep,
    super.canSkip = true,
  });

  bool _skip = false;

  void skip() => _skip = true;

  @override
  OnboardingStep? get nextStep => null;

  @override
  Future<void> execute() async {
    if (_skip) return;
    // GABBY TODO implement
  }
}
