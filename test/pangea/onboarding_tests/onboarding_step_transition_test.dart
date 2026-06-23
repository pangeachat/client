import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';
import 'get_initial_onboarding_step.dart';

void main() async {
  late final Client client;
  late final OnboardingNavigationController studentWithCode;
  late final OnboardingNavigationController studentWithoutCode;
  late final OnboardingNavigationController teacherWithCode;
  late final OnboardingNavigationController teacherWithoutCode;

  setUpAll(() async {
    client = await getTestClient();
    studentWithCode = OnboardingNavigationController(
      initialStep: getInitialOnboardingStep(client),
    );

    studentWithoutCode = OnboardingNavigationController(
      initialStep: getInitialOnboardingStep(client),
    );

    teacherWithCode = OnboardingNavigationController(
      initialStep: getInitialOnboardingStep(client),
    );

    teacherWithoutCode = OnboardingNavigationController(
      initialStep: getInitialOnboardingStep(client),
    );
  });

  void testForwardNavigationWithCode(
    OnboardingNavigationController state,
    UserType type,
  ) async {
    assert(await state.forward() is SuccessNavigationResult);
    assert(state.step is UserTypeOnboardingStep);
    assert(await state.forward() is ErrorNavigationResult);

    final userTypeStep = state.step as UserTypeOnboardingStep;
    userTypeStep.setUserType(type);

    assert(await state.forward() is SuccessNavigationResult);
    assert(state.step is CourseCodeOnboardingStep);
    assert(await state.forward() is ErrorNavigationResult);

    final courseCodeStep = state.step as CourseCodeOnboardingStep;
    courseCodeStep.setCourseCode('as12d45');

    assert(await state.forward() is SuccessNavigationResult);
    assert(state.step is JoinedCourseOnboardingStep);
    assert(await state.forward() is ReachedEndNavigationResult);
  }

  void testBackwardNavigationWithCode(OnboardingNavigationController state) {
    assert(state.step is JoinedCourseOnboardingStep);
    assert(state.back() is SuccessNavigationResult);
    assert(state.step is CourseCodeOnboardingStep);
    assert(state.back() is SuccessNavigationResult);
    assert(state.step is UserTypeOnboardingStep);
    assert(state.back() is SuccessNavigationResult);
    assert(state.step is ProfileSetupOnboardingStep);
    assert(state.back() is ReachedBeginningNavigationResult);
  }

  void testForwardNavigationWithoutCode(
    OnboardingNavigationController state,
    UserType type,
  ) async {
    assert(await state.forward() is SuccessNavigationResult);
    assert(state.step is UserTypeOnboardingStep);

    assert(await state.forward() is ErrorNavigationResult);
    assert(state.step is UserTypeOnboardingStep);

    final userTypeStep = state.step as UserTypeOnboardingStep;
    userTypeStep.setUserType(type);

    assert(await state.forward() is SuccessNavigationResult);
    assert(state.step is CourseCodeOnboardingStep);

    assert(await state.forward() is ErrorNavigationResult);
    assert(state.step is CourseCodeOnboardingStep);

    assert(state.skip() is SuccessNavigationResult);
    assert(state.step is PickLanguageOnboardingStep);

    assert(await state.forward() is ErrorNavigationResult);
    assert(state.step is PickLanguageOnboardingStep);

    final languageStep = state.step as PickLanguageOnboardingStep;
    languageStep.selectBaseLanguage(
      LanguageModel(langCode: "en", displayName: "English"),
    );
    languageStep.selectTargetLanguage(
      LanguageModel(langCode: "es", displayName: "Spanish"),
    );

    assert(await state.forward() is SuccessNavigationResult);
    assert(state.step is PickCefrLevelOnboardingStep);

    assert(await state.forward() is ErrorNavigationResult);
    assert(state.step is PickCefrLevelOnboardingStep);
    final levelStep = state.step as PickCefrLevelOnboardingStep;
    levelStep.selectCefrLevel(LanguageLevelTypeEnum.a1);

    switch (type) {
      case UserType.student:
        assert(await state.forward() is ReachedEndNavigationResult);
        return;
      case UserType.teacher:
        assert(await state.forward() is SuccessNavigationResult);
        assert(state.step is CustomCourseOnboardingStep);
        assert(await state.forward() is ErrorNavigationResult);
        assert(state.step is CustomCourseOnboardingStep);
        final step = state.step as CustomCourseOnboardingStep;
        step.setName("Course Name");
        step.setInstitution("Test University");
        step.setGoals("Test goals");
        assert(await state.forward() is ReachedEndNavigationResult);
        return;
    }
  }

  void testBackwardNavigationWithoutCode(
    OnboardingNavigationController state,
    UserType type,
  ) {
    if (type == UserType.teacher) {
      assert(state.back() is SuccessNavigationResult);
      assert(state.step is PickCefrLevelOnboardingStep);
    }

    assert(state.back() is SuccessNavigationResult);
    assert(state.step is PickLanguageOnboardingStep);

    assert(state.back() is SuccessNavigationResult);
    assert(state.step is CourseCodeOnboardingStep);

    assert(state.back() is SuccessNavigationResult);
    assert(state.step is UserTypeOnboardingStep);

    assert(state.back() is SuccessNavigationResult);
    assert(state.step is ProfileSetupOnboardingStep);

    assert(state.back() is ReachedBeginningNavigationResult);
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
