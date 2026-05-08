import 'package:fluffychat/pangea/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';

class UserTypeOnboardingStep extends OnboardingStep {
  UserTypeOnboardingStep({
    required super.client,
    super.stepIndex = 2,
    super.totalSteps = 6,
    required super.prevStep,
  });

  UserType? _userType;

  UserType? get userType => _userType;

  void setUserType(UserType type) => _userType = type;

  @override
  bool get enableGoForward => _userType != null;

  OnboardingStep? _getNextStep() {
    final type = _userType;
    if (type == null) {
      throw StateError("Must set user type to move to next step");
    }

    final totalSteps = switch (type) {
      UserType.student => 5,
      UserType.teacher => 6,
    };

    return CourseCodeOnboardingStep(
      prevStep: this,
      totalSteps: totalSteps,
      type: type,
      client: client,
    );
  }

  @override
  Future<OnboardingStep?> execute() async => _getNextStep();

  @override
  OnboardingStep? skip() => _getNextStep();
}
