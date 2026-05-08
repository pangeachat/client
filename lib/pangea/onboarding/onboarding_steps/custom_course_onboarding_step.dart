import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class CustomCourseOnboardingStep extends OnboardingStep {
  CustomCourseOnboardingStep({
    required super.client,
    super.stepIndex = 6,
    super.totalSteps = 6,
    required super.prevStep,
    super.enableSkip = true,
  });

  String? _name;
  String? _about;

  void setName(String name) => _name = name;
  void setAbout(String about) => _about = about;

  @override
  Future<OnboardingStep?> execute() async => null;

  @override
  OnboardingStep? skip() => null;
}
