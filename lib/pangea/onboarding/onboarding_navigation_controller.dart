import 'dart:collection';
import 'dart:math';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';

class OnboardingNavigationController {
  late OnboardingStep _currentStep;

  OnboardingNavigationController({required OnboardingStep initialStep}) {
    _currentStep = initialStep;
  }

  int _currentStepIndex = 1;

  final Queue<OnboardingStep> _prevSteps = Queue();

  OnboardingStep get step => _currentStep;

  bool get hasNextStep => _currentStep.maxRemainingSteps > 0;
  bool get hasPrevStep => _prevSteps.isNotEmpty;

  double get progress => max(
    0.0,
    min(
      1.0,
      _currentStepIndex / (_currentStepIndex + _currentStep.maxRemainingSteps),
    ),
  );

  Future<NavigationResult> forward() async {
    try {
      final nextStep = await _currentStep.execute();
      if (nextStep == null) {
        return ReachedEndNavigationResult();
      }

      _currentStepIndex++;
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

      _currentStepIndex++;
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

    _currentStepIndex--;
    _currentStep = prevStep;
    return SuccessNavigationResult(prevStep);
  }
}
