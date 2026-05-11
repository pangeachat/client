import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/pangea/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/get_localized_courses_request.dart';
import 'package:fluffychat/pangea/custom_courses/custom_course_response_model.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_navigation_result.dart';
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

void main() async {
  late final Client client;
  late final OnboardingStepState studentWithCode;
  late final OnboardingStepState studentWithoutCode;
  late final OnboardingStepState teacherWithCode;
  late final OnboardingStepState teacherWithoutCode;

  Uri getRandomAvatarUrl() => Uri.parse(
    "https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com/avatar_5.png",
  );

  Future<CoursePlanModel> getCoursePlan(
    GetLocalizedCoursesRequest request,
  ) async {
    return CoursePlanModel(
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
  }

  Future<Result<JoinResponse>> joinSpace(String code, Client client) async {
    return Result.value(
      JoinResponse(
        roomId: '!aeSvkSZmeiXqgwLVNS:staging.pangea.chat',
        shouldShowNotice: false,
      ),
    );
  }

  setUpAll(() async {
    client = await getTestClient();
    studentWithCode = OnboardingStepState(
      initialStep: getInitialOnboardingStep(client, getRandomAvatarUrl),
    );

    studentWithoutCode = OnboardingStepState(
      initialStep: getInitialOnboardingStep(client, getRandomAvatarUrl),
    );

    teacherWithCode = OnboardingStepState(
      initialStep: getInitialOnboardingStep(client, getRandomAvatarUrl),
    );

    teacherWithoutCode = OnboardingStepState(
      initialStep: getInitialOnboardingStep(client, getRandomAvatarUrl),
    );
  });

  void testForwardNavigationWithCode(
    OnboardingStepState state,
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
    courseCodeStep.setup(
      getCoursePlan,
      joinSpace,
      (_) async {},
      (_) async => "49e6b07f-cf95-44df-9790-3829dce72a12",
    );
    courseCodeStep.setCourseCode('as12d45');

    assert(await state.forward() is SuccessNavigationResult);
    assert(state.step is JoinedCourseOnboardingStep);
    assert(await state.forward() is ReachedEndNavigationResult);
  }

  void testBackwardNavigationWithCode(OnboardingStepState state) {
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
    OnboardingStepState state,
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
    languageStep.setup((_) async {});
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
    levelStep.setup((_) async {});
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
        step.setup(
          (_) async => Result.value(
            CustomCourseResponseModel(id: "123", status: "generating"),
          ),
        );
        step.setName("Course Name");
        step.setInstitution("Test University");
        step.setGoals("Test goals");
        assert(await state.forward() is ReachedEndNavigationResult);
        return;
    }
  }

  void testBackwardNavigationWithoutCode(
    OnboardingStepState state,
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
