import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_join_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';

/// #8593 — a class link joined the course and then asked the new user for a
/// class code. The join had succeeded; loading the course's quest had not, and
/// onboarding treated the pair as one outcome. A joined course now always
/// finishes on the joined-course page, and the user is asked only for what the
/// quest could not supply. See `joining-courses.instructions.md`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  const userId = '@test:fakeServer.notExisting';
  const spaceId = '!course:fakeServer.notExisting';

  /// The device language onboarding pairs a course's language with — English
  /// unless the test machine reports one of the seeded languages — and a course
  /// language guaranteed to differ from it.
  late final String baseLanguage;
  late final String otherLanguage;

  setUpAll(() async {
    // The steps resolve language codes through the store, so seed it rather
    // than let it fetch.
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {'language_code': 'en', 'language_name': 'English'},
          {
            'language_code': 'de',
            'language_name': 'German',
            'l2_support': 'full',
          },
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
        ],
      }),
    });
    await PLanguageStore.initialize();

    baseLanguage = LanguageService.systemLanguage?.langCodeShort ?? 'en';
    otherLanguage = baseLanguage == 'de' ? 'es' : 'de';
  });

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  /// A course space carrying a course-plan state event, as the client sees it
  /// after the join. [courseLanguage] null reproduces a space created before
  /// the language was recorded — the old spaces, which are also the ones whose
  /// quests no longer resolve.
  void registerCourseSpace({String? courseLanguage}) {
    final space = Room(
      id: spaceId,
      client: client,
      membership: Membership.join,
    );
    space.setState(
      Event(
        type: PangeaEventTypes.coursePlan,
        content: CoursePlanEvent(uuid: 'quest-1', l2: courseLanguage).toJson(),
        stateKey: '',
        senderId: userId,
        eventId: '\$course_plan',
        originServerTs: DateTime.utc(2026, 1, 1),
        room: space,
      ),
    );
    client.rooms.add(space);
  }

  OnboardingNavigationController controllerWithCachedCode() =>
      OnboardingNavigationController(
        initialStep: ProfileSetupOnboardingStep(
          client: client,
          state: OnboardingStateController(
            accountUpdater: MockAccountUpdater(),
            courseProvider: _QuestlessCourseProvider(roomId: spaceId),
            avatarProvider: MockAvatarProvider(),
            trialInfoProvider: MockTrialInfoProvider(),
          ),
          maxRemainingSteps: 5,
        ),
      );

  /// Drive profile setup and the role pick, which is where the ferried code is
  /// redeemed.
  Future<OnboardingNavigationController> joinedAs(UserType type) async {
    final state = controllerWithCachedCode();
    expect(await state.forward(), isA<SuccessNavigationResult>());
    (state.step as UserTypeOnboardingStep).setUserType(type);
    expect(await state.forward(), isA<SuccessNavigationResult>());
    return state;
  }

  group('CourseJoinStep.canUseCourseLanguage', () {
    final german = LanguageModel(langCode: 'de', displayName: 'German');
    final english = LanguageModel(langCode: 'en', displayName: 'English');

    test('a space that records no language cannot stand in for the pick', () {
      expect(CourseJoinStep.canUseCourseLanguage(null, english), isFalse);
    });

    test('a course in the base language cannot stand in for the pick', () {
      expect(CourseJoinStep.canUseCourseLanguage(english, english), isFalse);
      // Region variants are the same language to a learner.
      expect(
        CourseJoinStep.canUseCourseLanguage(
          LanguageModel(langCode: 'en-GB', displayName: 'English (UK)'),
          english,
        ),
        isFalse,
      );
    });

    test('a course in another language stands in for the pick', () {
      expect(CourseJoinStep.canUseCourseLanguage(german, english), isTrue);
    });
  });

  test('a space with no recorded language asks for both languages', () async {
    registerCourseSpace();
    final state = await joinedAs(UserType.student);

    // The code step is what #8593 showed here.
    expect(state.step, isA<PickLanguageOnboardingStep>());
    expect(state.step.state.joinedRoomId, spaceId);
  });

  test('a space that records its language asks only for the level', () async {
    registerCourseSpace(courseLanguage: otherLanguage);
    final state = await joinedAs(UserType.student);

    expect(state.step, isA<PickCefrLevelOnboardingStep>());
    expect(state.step.state.targetLanguage?.langCodeShort, otherLanguage);
    expect(state.step.state.baseLanguage?.langCodeShort, baseLanguage);
  });

  test('a learner ends on the joined-course page', () async {
    registerCourseSpace(courseLanguage: otherLanguage);
    final state = await joinedAs(UserType.student);

    (state.step as PickCefrLevelOnboardingStep).selectCefrLevel(
      LanguageLevelTypeEnum.a1,
    );
    expect(await state.forward(), isA<SuccessNavigationResult>());
    expect(state.step, isA<JoinedCourseOnboardingStep>());
    expect(state.step.joinedCourseSpaceId, spaceId);
    expect(await state.forward(), isA<ReachedEndNavigationResult>());
  });

  test(
    'a teacher ends on the joined-course page, not the course request',
    () async {
      registerCourseSpace(courseLanguage: otherLanguage);
      final state = await joinedAs(UserType.teacher);

      (state.step as PickCefrLevelOnboardingStep).selectCefrLevel(
        LanguageLevelTypeEnum.b1,
      );
      expect(await state.forward(), isA<SuccessNavigationResult>());
      expect(state.step, isA<JoinedCourseOnboardingStep>());
      expect(state.step, isNot(isA<CustomCourseOnboardingStep>()));
    },
  );
}

/// A course that joins but whose quest does not resolve — an orphaned space, or
/// a content service that did not answer.
class _QuestlessCourseProvider extends MockCourseProvider {
  final String roomId;

  _QuestlessCourseProvider({required this.roomId});

  @override
  String? getCachedJoinCode() => 'as12d45';

  @override
  Future<String> joinSpaceWithCode(String code) async => roomId;

  @override
  Future<CoursePlanModel?> getCourseByRoomId(String roomId) async => null;
}
