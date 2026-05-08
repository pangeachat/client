import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_state.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';
import '../get_test_client.dart';
import 'get_initial_onboarding_step.dart';
import 'mock_avatar_provider.dart';
import 'mock_onboarding_step.dart';

void main() async {
  late final Client client;
  late final OnboardingStepState studentWithCode;
  late final OnboardingStepState studentWithoutCode;
  late final OnboardingStepState teacherWithCode;
  late final OnboardingStepState teacherWithoutCode;

  setUpAll(() async {
    client = await getTestClient();
    final avatarProvider = MockAvatarProvider();

    studentWithCode = OnboardingStepState(
      initialStep: getInitialOnboardingStep(avatarProvider, client),
    );

    studentWithoutCode = OnboardingStepState(
      initialStep: getInitialOnboardingStep(avatarProvider, client),
    );

    teacherWithCode = OnboardingStepState(
      initialStep: getInitialOnboardingStep(avatarProvider, client),
    );

    teacherWithoutCode = OnboardingStepState(
      initialStep: getInitialOnboardingStep(avatarProvider, client),
    );
  });

  test("Test initial onboarding step", () {
    final prevStep = MockOnboardingStep(
      stepIndex: 4,
      totalSteps: 5,
      client: client,
    );

    final initialStep = PickCefrLevelOnboardingStep(
      prevStep: prevStep,
      totalSteps: 5,
      type: UserType.student,
      client: client,
    );

    final localState = OnboardingStepState(initialStep: initialStep);
    assert(localState.step is PickCefrLevelOnboardingStep);
  });

  void testForwardNavigationWithCode(
    OnboardingStepState state,
    UserType type,
  ) async {
    assert(state.navigateForward() == NavigationResult.success);
    assert(state.step is UserTypeOnboardingStep);
    assert(state.navigateForward() == NavigationResult.error);

    final userTypeStep = state.step as UserTypeOnboardingStep;
    userTypeStep.setUserType(type);

    assert(state.navigateForward() == NavigationResult.success);
    assert(state.step is CourseCodeOnboardingStep);

    assert(state.navigateForward() == NavigationResult.error);
    final courseCodeStep = state.step as CourseCodeOnboardingStep;

    final coursePlan = CoursePlanModel(
      targetLanguage: "es",
      languageOfInstructions: "en",
      cefrLevel: LanguageLevelTypeEnum.a1,
      title: "Test Course",
      description: "Course for testing",
      topicIds: [],
      mediaIds: [],
      updatedAt: DateTime(2026, 5, 1),
      createdAt: DateTime(2026, 5, 1),
      uuid: "49e6b07f-cf95-44df-9790-3829dce72a12",
    );
    courseCodeStep.setCoursePlan(coursePlan);

    assert(state.navigateForward() == NavigationResult.success);
    assert(state.step is JoinedCourseOnboardingStep);
    assert(state.navigateForward() == NavigationResult.reachedEnd);
  }

  void testBackwardNavigationWithCode(OnboardingStepState state) {
    assert(state.navigateBack() == NavigationResult.success);
    assert(state.step is CourseCodeOnboardingStep);

    assert(state.navigateBack() == NavigationResult.success);
    assert(state.step is UserTypeOnboardingStep);

    assert(state.navigateBack() == NavigationResult.success);
    assert(state.step is ProfileSetupOnboardingStep);

    assert(state.navigateBack() == NavigationResult.reachedBeginning);
  }

  void testForwardNavigationWithoutCode(
    OnboardingStepState state,
    UserType type,
  ) {
    assert(state.navigateForward() == NavigationResult.success);
    assert(state.step is UserTypeOnboardingStep);

    assert(state.navigateForward() == NavigationResult.error);
    assert(state.step is UserTypeOnboardingStep);

    final userTypeStep = state.step as UserTypeOnboardingStep;
    userTypeStep.setUserType(type);

    assert(state.navigateForward() == NavigationResult.success);
    assert(state.step is CourseCodeOnboardingStep);

    assert(state.navigateForward() == NavigationResult.error);
    assert(state.step is CourseCodeOnboardingStep);

    final courseCodeStep = state.step as CourseCodeOnboardingStep;
    courseCodeStep.skip();

    assert(state.navigateForward() == NavigationResult.success);
    assert(state.step is PickLanguageOnboardingStep);

    assert(state.navigateForward() == NavigationResult.error);
    assert(state.step is PickLanguageOnboardingStep);
    final languageStep = state.step as PickLanguageOnboardingStep;
    languageStep.selectBaseLanguage(
      LanguageModel(langCode: "en", displayName: "English"),
    );
    languageStep.selectTargetLanguage(
      LanguageModel(langCode: "es", displayName: "Spanish"),
    );

    assert(state.navigateForward() == NavigationResult.success);
    assert(state.step is PickCefrLevelOnboardingStep);

    assert(state.navigateForward() == NavigationResult.error);
    assert(state.step is PickCefrLevelOnboardingStep);
    final levelStep = state.step as PickCefrLevelOnboardingStep;
    levelStep.selectCefrLevel(LanguageLevelTypeEnum.a1);

    switch (type) {
      case UserType.student:
        assert(state.navigateForward() == NavigationResult.reachedEnd);
        return;
      case UserType.teacher:
        assert(state.navigateForward() == NavigationResult.success);
        assert(state.step is CustomCourseOnboardingStep);
        assert(state.navigateForward() == NavigationResult.reachedEnd);
        return;
    }
  }

  void testBackwardNavigationWithoutCode(
    OnboardingStepState state,
    UserType type,
  ) {
    if (type == UserType.teacher) {
      assert(state.navigateBack() == NavigationResult.success);
      assert(state.step is PickCefrLevelOnboardingStep);
    }

    assert(state.navigateBack() == NavigationResult.success);
    assert(state.step is PickLanguageOnboardingStep);

    assert(state.navigateBack() == NavigationResult.success);
    assert(state.step is CourseCodeOnboardingStep);

    assert(state.navigateBack() == NavigationResult.success);
    assert(state.step is UserTypeOnboardingStep);

    assert(state.navigateBack() == NavigationResult.success);
    assert(state.step is ProfileSetupOnboardingStep);

    assert(state.navigateBack() == NavigationResult.reachedBeginning);
  }

  test("Test forward navigation for student with code", () {
    testForwardNavigationWithCode(studentWithCode, UserType.student);
  });

  test("Test backward navigation for student with code", () {
    testBackwardNavigationWithCode(studentWithCode);
  });

  test("Test forward navigation through student without course path", () {
    testForwardNavigationWithoutCode(studentWithoutCode, UserType.student);
  });

  test("Test backward navigation through student without course path", () {
    testBackwardNavigationWithoutCode(studentWithoutCode, UserType.student);
  });

  test("Test forward navigation through teacher with course code", () {
    testForwardNavigationWithCode(teacherWithCode, UserType.teacher);
  });

  test("Test backward navigation through teacher with course code", () {
    testBackwardNavigationWithCode(teacherWithCode);
  });

  test("Test forward navigation through teacher without course code", () {
    testForwardNavigationWithoutCode(teacherWithoutCode, UserType.teacher);
  });

  test("Test backward navigation through teacher without course code", () {
    testBackwardNavigationWithoutCode(teacherWithoutCode, UserType.teacher);
  });
}
