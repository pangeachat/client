import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class MockOnboardingStep extends OnboardingStep {
  const MockOnboardingStep({
    required super.client,
    required super.stepIndex,
    required super.totalSteps,
    super.prevStep,
  });

  @override
  OnboardingStep? get nextStep => null;
}
