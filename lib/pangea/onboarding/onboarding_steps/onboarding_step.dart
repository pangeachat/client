import 'package:matrix/matrix.dart';

abstract class OnboardingStep {
  final int stepIndex;
  final int totalSteps;
  final Client client;
  final OnboardingStep? prevStep;
  final bool enableSkip;

  const OnboardingStep({
    required this.stepIndex,
    required this.totalSteps,
    required this.client,
    this.prevStep,
    this.enableSkip = false,
  });

  bool get hasPrevStep => prevStep != null;
  bool get hasNextStep => stepIndex < totalSteps;

  bool get enableGoForward => true;

  String get stepDestination => "/rooms";

  Future<OnboardingStep?> execute();

  OnboardingStep? skip();
}
