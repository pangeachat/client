import 'package:matrix/matrix.dart';

abstract class OnboardingStep {
  final Client client;
  final int maxTotalSteps;
  final bool enableSkip;

  const OnboardingStep({
    required this.client,
    required this.maxTotalSteps,
    this.enableSkip = false,
  });

  bool get enableGoForward => true;

  String get stepDestination => "/rooms";

  Future<OnboardingStep?> execute();

  OnboardingStep? skip();
}
