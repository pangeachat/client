import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';

abstract class OnboardingStep {
  final Client client;
  final OnboardingStateController state;
  final int maxRemainingSteps;

  const OnboardingStep({
    required this.client,
    required this.state,
    required this.maxRemainingSteps,
  });

  bool get enableGoForward => true;

  String get stepDestination => "/rooms";

  String nextStepText(L10n l10n) => l10n.next;

  String lastStepText(L10n l10n) => l10n.letsGo;

  Future<OnboardingStep?> execute();

  OnboardingStep? skip();
}
