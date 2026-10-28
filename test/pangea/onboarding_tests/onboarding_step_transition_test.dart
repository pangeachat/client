import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/central_course_onboarding_step.dart';
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

void main() {
  late final Client client;

  setUpAll(() async {
    client = await getTestClient();
  });

  // Each test builds its own controller and drives it to the state it needs, so
  // tests stay independent under any ordering. Helpers return Futures that the
  // test bodies await — an un-awaited navigation chain outlives its test and
  // races the next one (the source of the old CI flake).
  OnboardingNavigationController createController() =>
      OnboardingNavigationController(
        initialStep: getInitialOnboardingStep(client),
      );

  Future<void> testForwardNavigationWithCode(
    OnboardingNavigationController state,
    UserType type,
  ) async {
    expect(await state.forward(), isA<SuccessNavigationResult>());
    expect(state.step, isA<UserTypeOnboardingStep>());
    expect(await state.forward(), isA<ErrorNavigationResult>());

    final userTypeStep = state.step as UserTypeOnboardingStep;
    userTypeStep.setUserType(type);

    expect(await state.forward(), isA<SuccessNavigationResult>());
    expect(state.step, isA<CourseCodeOnboardingStep>());
    expect(await state.forward(), isA<ErrorNavigationResult>());

    final courseCodeStep = state.step as CourseCodeOnboardingStep;
    courseCodeStep.setCourseCode('as12d45');

    expect(await state.forward(), isA<SuccessNavigationResult>());
    expect(state.step, isA<JoinedCourseOnboardingStep>());
    expect(await state.forward(), isA<ReachedEndNavigationResult>());
  }

  void testBackwardNavigationWithCode(OnboardingNavigationController state) {
    expect(state.step, isA<JoinedCourseOnboardingStep>());
    expect(state.back(), isA<SuccessNavigationResult>());
    expect(state.step, isA<CourseCodeOnboardingStep>());
    expect(state.back(), isA<SuccessNavigationResult>());
    expect(state.step, isA<UserTypeOnboardingStep>());
    expect(state.back(), isA<SuccessNavigationResult>());
    expect(state.step, isA<ProfileSetupOnboardingStep>());
    expect(state.back(), isA<ReachedBeginningNavigationResult>());
  }

  Future<void> testForwardNavigationWithoutCode(
    OnboardingNavigationController state,
    UserType type,
  ) async {
    expect(await state.forward(), isA<SuccessNavigationResult>());
    expect(state.step, isA<UserTypeOnboardingStep>());

    expect(await state.forward(), isA<ErrorNavigationResult>());
    expect(state.step, isA<UserTypeOnboardingStep>());

    final userTypeStep = state.step as UserTypeOnboardingStep;
    userTypeStep.setUserType(type);

    expect(await state.forward(), isA<SuccessNavigationResult>());
    expect(state.step, isA<CourseCodeOnboardingStep>());

    expect(await state.forward(), isA<ErrorNavigationResult>());
    expect(state.step, isA<CourseCodeOnboardingStep>());

    expect(state.skip(), isA<SuccessNavigationResult>());
    expect(state.step, isA<PickLanguageOnboardingStep>());

    expect(await state.forward(), isA<ErrorNavigationResult>());
    expect(state.step, isA<PickLanguageOnboardingStep>());

    final languageStep = state.step as PickLanguageOnboardingStep;
    languageStep.selectBaseLanguage(
      LanguageModel(langCode: "en", displayName: "English"),
    );
    languageStep.selectTargetLanguage(
      LanguageModel(langCode: "es", displayName: "Spanish"),
    );

    expect(await state.forward(), isA<SuccessNavigationResult>());
    expect(state.step, isA<PickCefrLevelOnboardingStep>());

    expect(await state.forward(), isA<ErrorNavigationResult>());
    expect(state.step, isA<PickCefrLevelOnboardingStep>());
    final levelStep = state.step as PickCefrLevelOnboardingStep;
    levelStep.selectCefrLevel(LanguageLevelTypeEnum.a1);

    switch (type) {
      case UserType.student:
        expect(await state.forward(), isA<ReachedEndNavigationResult>());
        return;
      case UserType.teacher:
        expect(await state.forward(), isA<SuccessNavigationResult>());
        expect(state.step, isA<CustomCourseOnboardingStep>());
        expect(await state.forward(), isA<ErrorNavigationResult>());
        expect(state.step, isA<CustomCourseOnboardingStep>());
        final step = state.step as CustomCourseOnboardingStep;
        step.setName("Course Name");
        step.setInstitution("Test University");
        step.setGoals("Test goals");
        expect(await state.forward(), isA<ReachedEndNavigationResult>());
        return;
    }
  }

  void testBackwardNavigationWithoutCode(
    OnboardingNavigationController state,
    UserType type,
  ) {
    if (type == UserType.teacher) {
      expect(state.back(), isA<SuccessNavigationResult>());
      expect(state.step, isA<PickCefrLevelOnboardingStep>());
    }

    expect(state.back(), isA<SuccessNavigationResult>());
    expect(state.step, isA<PickLanguageOnboardingStep>());

    expect(state.back(), isA<SuccessNavigationResult>());
    expect(state.step, isA<CourseCodeOnboardingStep>());

    expect(state.back(), isA<SuccessNavigationResult>());
    expect(state.step, isA<UserTypeOnboardingStep>());

    expect(state.back(), isA<SuccessNavigationResult>());
    expect(state.step, isA<ProfileSetupOnboardingStep>());

    expect(state.back(), isA<ReachedBeginningNavigationResult>());
  }

  test("Test forward navigation for student with code", () async {
    await testForwardNavigationWithCode(createController(), UserType.student);
  });

  test("Test backward navigation for student with code", () async {
    final state = createController();
    await testForwardNavigationWithCode(state, UserType.student);
    testBackwardNavigationWithCode(state);
  });

  test("Test forward navigation through student without course path", () async {
    await testForwardNavigationWithoutCode(
      createController(),
      UserType.student,
    );
  });

  test(
    "Test backward navigation through student without course path",
    () async {
      final state = createController();
      await testForwardNavigationWithoutCode(state, UserType.student);
      testBackwardNavigationWithoutCode(state, UserType.student);
    },
  );

  test("Test forward navigation through teacher with course code", () async {
    await testForwardNavigationWithCode(createController(), UserType.teacher);
  });

  test("Test backward navigation through teacher with course code", () async {
    final state = createController();
    await testForwardNavigationWithCode(state, UserType.teacher);
    testBackwardNavigationWithCode(state);
  });

  test("Test forward navigation through teacher without course code", () async {
    await testForwardNavigationWithoutCode(
      createController(),
      UserType.teacher,
    );
  });

  test(
    "Test backward navigation through teacher without course code",
    () async {
      final state = createController();
      await testForwardNavigationWithoutCode(state, UserType.teacher);
      testBackwardNavigationWithoutCode(state, UserType.teacher);
    },
  );

  // A learner with no class code chooses, after the level step, between their
  // language's central course and a private course of their own; with no
  // central course they get their own course, repaired later
  // (joining-courses.instructions.md § The central course).
  Future<OnboardingNavigationController> toLevelStep(
    UserType type,
    MockCourseProvider courses,
  ) async {
    final state = OnboardingNavigationController(
      initialStep: getInitialOnboardingStep(client, courses: courses),
    );
    await state.forward();
    (state.step as UserTypeOnboardingStep).setUserType(type);
    await state.forward();
    state.skip();
    (state.step as PickLanguageOnboardingStep)
      ..selectBaseLanguage(
        LanguageModel(langCode: "en", displayName: "English"),
      )
      ..selectTargetLanguage(
        LanguageModel(langCode: "es", displayName: "Spanish"),
      );
    await state.forward();
    (state.step as PickCefrLevelOnboardingStep).selectCefrLevel(
      LanguageLevelTypeEnum.a1,
    );
    return state;
  }

  const central = '!central:staging.pangea.chat';

  test("A learner who joins the central course lands on it", () async {
    final courses = MockCourseProvider(centralCourseRoomId: central);
    final state = await toLevelStep(UserType.student, courses);

    expect(await state.forward(), isA<SuccessNavigationResult>());
    expect(state.step, isA<CentralCourseOnboardingStep>());
    (state.step as CentralCourseOnboardingStep).chooseOwnCourse(false);
    expect(await state.forward(), isA<ReachedEndNavigationResult>());
    expect(state.step.joinedCourseSpaceId, central);
    expect(courses.ownCoursePlans, isEmpty);
  });

  test("A learner who declines gets their own course on its plan", () async {
    final courses = MockCourseProvider(centralCourseRoomId: central);
    final state = await toLevelStep(UserType.student, courses);

    expect(await state.forward(), isA<SuccessNavigationResult>());
    (state.step as CentralCourseOnboardingStep).chooseOwnCourse(true);
    expect(await state.forward(), isA<ReachedEndNavigationResult>());
    expect(state.step.joinedCourseSpaceId, MockCourseProvider.ownCourseRoomId);
    expect(courses.ownCoursePlans, [MockCourseProvider.centralQuestId]);
  });

  test(
    "With no central course, a learner gets a course with no plan",
    () async {
      final courses = MockCourseProvider();
      final state = await toLevelStep(UserType.student, courses);

      expect(await state.forward(), isA<ReachedEndNavigationResult>());
      expect(courses.ownCoursePlans, [null]);
      // A course with no plan has nothing to show yet, so they land on the map.
      expect(state.step.joinedCourseSpaceId, isNull);
    },
  );

  test(
    "A teacher without a code is neither asked nor given a course",
    () async {
      final courses = MockCourseProvider(centralCourseRoomId: central);
      final state = await toLevelStep(UserType.teacher, courses);

      expect(await state.forward(), isA<SuccessNavigationResult>());
      expect(state.step, isA<CustomCourseOnboardingStep>());
      expect(state.step.joinedCourseSpaceId, isNull);
      expect(courses.ownCoursePlans, isEmpty);
    },
  );

  test("Switching role clears a stale CEFR selection (#7583)", () {
    final state = getInitialOnboardingStep(client).state;

    // Pick a CEFR level as a teacher.
    state.setUserType(UserType.teacher);
    state.setLanguageLevel(LanguageLevelTypeEnum.a1);
    expect(state.languageLevel, LanguageLevelTypeEnum.a1);

    // Switching to learner must NOT carry the teacher's level over — otherwise
    // the learner CEFR page shows nothing selected while Next stays enabled.
    state.setUserType(UserType.student);
    expect(state.languageLevel, isNull);

    final levelStep = PickCefrLevelOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: 0,
    );
    expect(levelStep.enableGoForward, isFalse);

    // Re-tapping the same role keeps a real selection.
    state.setLanguageLevel(LanguageLevelTypeEnum.b1);
    state.setUserType(UserType.student);
    expect(state.languageLevel, LanguageLevelTypeEnum.b1);
    expect(levelStep.enableGoForward, isTrue);
  });
}
