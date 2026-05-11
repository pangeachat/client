import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class MockOnboardingStep extends OnboardingStep {
  const MockOnboardingStep({
    required super.client,
    required super.maxTotalSteps,
  });

  @override
  Future<OnboardingStep?> execute() async => null;

  @override
  OnboardingStep? skip() => null;
}
