import 'package:fluffychat/pangea/languages/language_model.dart';

class OnboardingNavigationButtonState {
  final bool enabled;
  final LanguageModel? target;

  const OnboardingNavigationButtonState({
    required this.enabled,
    required this.target,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is OnboardingNavigationButtonState &&
        other.enabled == enabled &&
        other.target == target;
  }

  @override
  int get hashCode => Object.hash(enabled, target);
}
