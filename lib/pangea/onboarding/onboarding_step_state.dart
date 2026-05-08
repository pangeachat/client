import 'package:fluffychat/pangea/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class OnboardingStepState {
  late OnboardingStep _currentStep;

  OnboardingStepState({required OnboardingStep initialStep}) {
    _currentStep = initialStep;
  }

  OnboardingStep get step => _currentStep;

  Future<NavigationResult> forward() async {
    try {
      final nextStep = await _currentStep.execute();
      if (nextStep == null) {
        return ReachedEndNavigationResult();
      }

      _currentStep = nextStep;
      return SuccessNavigationResult();
    } catch (e) {
      return ErrorNavigationResult(e);
    }
  }

  NavigationResult skip() {
    try {
      final nextStep = _currentStep.skip();
      if (nextStep == null) {
        return ReachedEndNavigationResult();
      }

      _currentStep = nextStep;
      return SuccessNavigationResult();
    } catch (e) {
      return ErrorNavigationResult(e);
    }
  }

  NavigationResult back() {
    final prevStep = _currentStep.prevStep;
    if (prevStep == null) {
      return ReachedBeginningNavigationResult();
    }

    _currentStep = prevStep;
    return SuccessNavigationResult();
  }
}
