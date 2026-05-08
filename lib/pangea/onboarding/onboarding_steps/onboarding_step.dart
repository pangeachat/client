import 'package:matrix/matrix.dart';

abstract class OnboardingStep {
  final int stepIndex;
  final int totalSteps;
  final Client client;
  final OnboardingStep? prevStep;
  final bool canSkip;

  const OnboardingStep({
    required this.stepIndex,
    required this.totalSteps,
    required this.client,
    this.prevStep,
    this.canSkip = false,
  });

  bool get hasPrevStep => prevStep != null;
  bool get hasNextStep => stepIndex < totalSteps;

  bool get enableGoBack => hasPrevStep;
  bool get enableGoForward => true;

  double get progress => stepIndex / totalSteps;

  OnboardingStep? get nextStep;

  String get stepDestination => "/rooms";

  Future<void> execute() async {
    throw UnimplementedError();
  }
}
