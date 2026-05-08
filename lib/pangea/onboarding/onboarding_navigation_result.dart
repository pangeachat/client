sealed class NavigationResult {}

class SuccessNavigationResult extends NavigationResult {}

class ReachedEndNavigationResult extends NavigationResult {}

class ReachedBeginningNavigationResult extends NavigationResult {}

class ErrorNavigationResult extends NavigationResult {
  final Object error;
  ErrorNavigationResult(this.error);
}
