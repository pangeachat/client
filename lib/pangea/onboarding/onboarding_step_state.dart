import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

enum NavigationResult { success, reachedEnd, reachedBeginning, error }

class OnboardingStepState {
  late OnboardingStep _currentStep;

  OnboardingStepState({required OnboardingStep initialStep}) {
    _currentStep = initialStep;
  }

  OnboardingStep get step => _currentStep;

  /// Return true if navigation was successful
  NavigationResult navigateForward() {
    try {
      final nextStep = _currentStep.nextStep;
      if (nextStep == null) {
        return NavigationResult.reachedEnd;
      }

      _currentStep = nextStep;
      return NavigationResult.success;
    } catch (e) {
      Logs().w("Failed to navigate onboarding forward");
      return NavigationResult.error;
    }
  }

  /// Return true if navigation was successful
  NavigationResult navigateBack() {
    final prevStep = _currentStep.prevStep;
    if (prevStep == null) {
      return NavigationResult.reachedBeginning;
    }

    _currentStep = prevStep;
    return NavigationResult.success;
  }
}
