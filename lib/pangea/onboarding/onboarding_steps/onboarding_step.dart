import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/onboarding/onboarding_state_controller.dart';

abstract class OnboardingStep {
  final Client client;
  final OnboardingStateController state;
  final int maxRemainingSteps;
  final bool enableSkip;

  const OnboardingStep({
    required this.client,
    required this.state,
    required this.maxRemainingSteps,
    this.enableSkip = false,
  });

  bool get enableGoForward => true;

  String get stepDestination => "/rooms";

  Future<OnboardingStep?> execute();

  OnboardingStep? skip();
}
