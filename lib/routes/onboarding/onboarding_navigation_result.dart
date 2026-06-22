import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';

sealed class NavigationResult {}

class SuccessNavigationResult extends NavigationResult {
  final OnboardingStep step;
  SuccessNavigationResult(this.step);
}

class ReachedEndNavigationResult extends NavigationResult {}

class ReachedBeginningNavigationResult extends NavigationResult {}

class ErrorNavigationResult extends NavigationResult {
  final Object error;
  ErrorNavigationResult(this.error);
}
