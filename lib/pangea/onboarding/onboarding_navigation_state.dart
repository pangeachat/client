import 'dart:collection';
import 'dart:math';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class OnboardingNavigationState {
  late OnboardingStep _currentStep;
  late int _stepIndex;

  OnboardingNavigationState({
    required OnboardingStep initialStep,
    int stepIndex = 1,
  }) {
    _currentStep = initialStep;
    _stepIndex = stepIndex;
  }

  final Queue<OnboardingStep> _prevSteps = Queue();

  OnboardingStep get step => _currentStep;

  bool get hasNextStep => _stepIndex < _currentStep.maxTotalSteps;
  bool get hasPrevStep => _prevSteps.isNotEmpty;

  double get progress =>
      max(0.0, min(1.0, _stepIndex / _currentStep.maxTotalSteps));

  Future<NavigationResult> forward() async {
    try {
      final nextStep = await _currentStep.execute();
      if (nextStep == null) {
        return ReachedEndNavigationResult();
      }

      _stepIndex++;
      _prevSteps.addLast(_currentStep);
      _currentStep = nextStep;
      return SuccessNavigationResult(nextStep);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'current_step': _currentStep});
      return ErrorNavigationResult(e);
    }
  }

  NavigationResult skip() {
    try {
      final nextStep = _currentStep.skip();
      if (nextStep == null) {
        return ReachedEndNavigationResult();
      }

      _stepIndex++;
      _prevSteps.addLast(_currentStep);
      _currentStep = nextStep;
      return SuccessNavigationResult(nextStep);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'current_step': _currentStep});
      return ErrorNavigationResult(e);
    }
  }

  NavigationResult back() {
    if (_prevSteps.isEmpty) {
      return ReachedBeginningNavigationResult();
    }

    final prevStep = _prevSteps.removeLast();

    _stepIndex--;
    _currentStep = prevStep;
    return SuccessNavigationResult(prevStep);
  }
}
