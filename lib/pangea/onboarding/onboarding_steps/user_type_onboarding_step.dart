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

  @override
  OnboardingStep? get nextStep {
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
  Future<void> execute() async {
    // GABBY TODO: store user type
  }
}
