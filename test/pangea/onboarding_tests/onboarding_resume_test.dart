import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' hide Profile;

import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_resume.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/free_trial_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';
import 'seed_language_store.dart';

/// An unfinished onboarding resumes from what is saved to the account. See
/// `onboarding.instructions.md` § What onboarding reads and saves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(seedLanguageStore);

  setUp(() async {
    client = await getTestClient();
    // An account-data write comes back in sync, as it does from the server.
    FakeMatrixApi.client = client;
  });

  tearDown(() async {
    FakeMatrixApi.client = null;
    await client.dispose();
  });

  void saveProgress(Map<String, Object?> content) =>
      client.accountData[PangeaEventTypes.onboardingProgress] = BasicEvent(
        type: PangeaEventTypes.onboardingProgress,
        content: content,
      );

  void saveSettings(Map<String, Object?> settings) =>
      client.accountData[UserConstants.userProfile] = BasicEvent(
        type: UserConstants.userProfile,
        content: {UserConstants.userSettings: settings},
      );

  OnboardingStateController newState({
    AccountUpdater? updater,
    TrialInfoProvider? trial,
  }) => OnboardingStateController(
    accountUpdater: updater ?? MockAccountUpdater(),
    courseProvider: MockCourseProvider(),
    avatarProvider: MockAvatarProvider(),
    trialInfoProvider: trial ?? MockTrialInfoProvider(),
    userType: client.selfIdentifiedRole,
  );

  group('the marks', () {
    test('an account with no marks is not resumed', () {
      saveSettings({'target_language': 'es', 'source_language': 'en'});
      expect(client.onboardingUnfinished, isFalse);
    });

    test('a started run that has not finished is resumed', () {
      saveProgress({'started': true});
      expect(client.onboardingUnfinished, isTrue);
    });

    test('a finished run is not resumed', () {
      saveProgress({'started': true, 'finished': true});
      expect(client.onboardingUnfinished, isFalse);
    });

    test('reaching the end lets the person in before the mark saves', () async {
      saveProgress({'started': true});
      final write = client.markOnboardingFinished();
      expect(client.onboardingUnfinished, isFalse);
      await write;
      expect(client.accountData[PangeaEventTypes.onboardingProgress]?.content, {
        'started': true,
        'finished': true,
      });
    });

    test('a run is marked started for an account with no L2', () async {
      await client.markOnboardingStarted();
      expect(client.onboardingUnfinished, isTrue);
    });

    test(
      'an account with an L2 and no marks is never marked started',
      () async {
        saveSettings({'target_language': 'es', 'source_language': 'en'});
        await client.markOnboardingStarted();
        expect(client.accountData[PangeaEventTypes.onboardingProgress], isNull);
        expect(client.onboardingUnfinished, isFalse);
      },
    );

    test('the profile mark carries the started mark', () async {
      await client.markOnboardingProfileSaved();
      expect(client.onboardingProfileSaved, isTrue);
      expect(client.accountData[PangeaEventTypes.onboardingProgress]?.content, {
        'started': true,
        'profile_saved': true,
      });
    });

    test('the level mark needs a started run', () async {
      await client.markOnboardingLevelSaved();
      expect(client.accountData[PangeaEventTypes.onboardingProgress], isNull);

      saveProgress({'started': true});
      await client.markOnboardingLevelSaved();
      expect(client.onboardingLevelSaved, isTrue);
      expect(client.accountData[PangeaEventTypes.onboardingProgress]?.content, {
        'started': true,
        'level_saved': true,
      });
    });

    test('an account with an L2 and no marks gets no profile mark', () async {
      saveSettings({'target_language': 'es', 'source_language': 'en'});
      await client.markOnboardingProfileSaved();
      expect(client.accountData[PangeaEventTypes.onboardingProgress], isNull);
    });
  });

  group('pressing Next on the profile page', () {
    ProfileSetupOnboardingStep profileStep(Client on) =>
        ProfileSetupOnboardingStep(
          client: on,
          state: newState(),
          maxRemainingSteps: 5,
        );

    test('marks it saved once its name and picture are saved', () async {
      await profileStep(client).execute();
      expect(client.onboardingProfileSaved, isTrue);
    });

    test('leaves it unmarked when the picture fails to save', () async {
      final failing = await getTestClient(
        name: 'failing_avatar',
        httpClient: _FailingAvatarApi(),
      );
      addTearDown(failing.dispose);
      // A wrong mark would come back in sync, so its absence means something.
      FakeMatrixApi.client = failing;

      expect(
        await profileStep(failing).execute(),
        isA<UserTypeOnboardingStep>(),
      );
      expect(failing.accountData[PangeaEventTypes.onboardingProgress], isNull);
    });
  });

  group('a resumed run opens on the first page with nothing saved', () {
    test('a run that is not resumed opens on the profile page', () {
      saveSettings({
        UserConstants.selfIdentifiedRole: 'student',
        'target_language': 'es',
        'source_language': 'en',
      });
      final path = resumedOnboardingPath(client, newState());
      expect(path.single, isA<ProfileSetupOnboardingStep>());
    });

    test('with nothing saved, on the profile page', () {
      saveProgress({'started': true});
      final path = resumedOnboardingPath(client, newState());
      expect(path.single, isA<ProfileSetupOnboardingStep>());
    });

    test('with the profile page saved and no role, on the role page', () {
      saveProgress({'started': true, 'profile_saved': true});
      final path = resumedOnboardingPath(client, newState());
      expect(path.map((s) => s.runtimeType), [
        ProfileSetupOnboardingStep,
        UserTypeOnboardingStep,
      ]);
    });

    test('with a role and no languages, on the class-code page', () {
      saveProgress({'started': true});
      saveSettings({UserConstants.selfIdentifiedRole: 'teacher'});
      final path = resumedOnboardingPath(client, newState());
      expect(path.map((s) => s.runtimeType), [
        ProfileSetupOnboardingStep,
        UserTypeOnboardingStep,
        CourseCodeOnboardingStep,
      ]);
      // Class code, languages, level, course request.
      expect(path.last.maxRemainingSteps, 3);
    });

    test('with languages saved, on the level page, carrying them', () {
      saveProgress({'started': true});
      saveSettings({
        UserConstants.selfIdentifiedRole: 'student',
        'target_language': 'es',
        'source_language': 'en',
      });
      final state = newState();
      final path = resumedOnboardingPath(client, state);
      expect(path.map((s) => s.runtimeType), [
        ProfileSetupOnboardingStep,
        UserTypeOnboardingStep,
        CourseCodeOnboardingStep,
        PickLanguageOnboardingStep,
        PickCefrLevelOnboardingStep,
      ]);
      expect(state.userType, UserType.student);
      expect(state.baseLanguage?.langCode, 'en');
      expect(state.targetLanguage?.langCode, 'es');
    });

    test('Back from the page it opens on goes to the page before', () {
      saveProgress({'started': true});
      saveSettings({
        UserConstants.selfIdentifiedRole: 'student',
        'target_language': 'es',
        'source_language': 'en',
      });
      final path = resumedOnboardingPath(client, newState());
      final nav = OnboardingNavigationController(
        initialStep: path.last,
        previousSteps: path.sublist(0, path.length - 1),
      );
      expect(nav.currentStepIndex, 5);
      expect(nav.hasPrevStep, isTrue);
      expect(nav.back(), isA<SuccessNavigationResult>());
      expect(nav.step, isA<PickLanguageOnboardingStep>());
      expect(nav.currentStepIndex, 4);
    });
  });

  group('the level is marked saved', () {
    PickCefrLevelOnboardingStep levelStep({AccountUpdater? updater}) =>
        PickCefrLevelOnboardingStep(
          client: client,
          state: newState(updater: updater)
            ..setUserType(UserType.student)
            ..setLanguageLevel(LanguageLevelTypeEnum.b2),
          maxRemainingSteps: 0,
        );

    test('by Next on the level page', () async {
      saveProgress({'started': true});
      await levelStep().execute();
      expect(client.onboardingLevelSaved, isTrue);
    });

    test('but not when its save fails', () async {
      saveProgress({'started': true});
      await levelStep(updater: _FailingUpdater()).execute();
      expect(client.onboardingLevelSaved, isFalse);
    });

    test('by a joined course that supplies it', () async {
      saveProgress({'started': true});
      final code = CourseCodeOnboardingStep(
        client: client,
        state: newState()..setUserType(UserType.student),
        maxRemainingSteps: 2,
      )..setCourseCode('abc1234');
      expect(await code.execute(), isA<JoinedCourseOnboardingStep>());
      expect(client.onboardingLevelSaved, isTrue);
    });
  });

  group('with the level saved, a resumed run opens past it', () {
    void saveThroughLevel(String role) {
      saveProgress({
        'started': true,
        'profile_saved': true,
        'level_saved': true,
      });
      saveSettings({
        UserConstants.selfIdentifiedRole: role,
        'target_language': 'es',
        'source_language': 'en',
        UserConstants.cefrLevel: 'B1',
      });
    }

    test('a learner on the trial page', () {
      saveThroughLevel('student');
      final path = resumedOnboardingPath(
        client,
        newState(trial: _ShowsTrialPage()),
      );
      expect(path.last, isA<FreeTrialOnboardingStep>());
      expect(path[path.length - 2], isA<PickCefrLevelOnboardingStep>());
    });

    test('a teacher on the course request, ready to send', () async {
      saveThroughLevel('teacher');
      final state = newState()
        ..setCourseRequestName('Ana')
        ..setCourseRequestInstitution('Lincoln High')
        ..setCourseRequestGoals('Avancemos 1');
      final path = resumedOnboardingPath(client, state);
      expect(path.last, isA<CustomCourseOnboardingStep>());
      expect(state.languageLevel, LanguageLevelTypeEnum.b1);
      // It throws if the saved languages and level aren't carried over.
      await path.last.execute();
    });

    test('on the level page when no page follows it', () {
      saveThroughLevel('student');
      final path = resumedOnboardingPath(client, newState());
      expect(path.last, isA<PickCefrLevelOnboardingStep>());
    });
  });

  group('a failed level save moves on', () {
    PickCefrLevelOnboardingStep levelStep(UserType role) =>
        PickCefrLevelOnboardingStep(
          client: client,
          state: newState(updater: _FailingUpdater())
            ..setUserType(role)
            ..setLanguageLevel(LanguageLevelTypeEnum.b2),
          maxRemainingSteps: 1,
        );

    test('for a teacher, to the course request', () async {
      expect(
        await levelStep(UserType.teacher).execute(),
        isA<CustomCourseOnboardingStep>(),
      );
    });

    test('for a learner with no trial page, to the end', () async {
      final nav = OnboardingNavigationController(
        initialStep: levelStep(UserType.student),
      );
      expect(await nav.forward(), isA<ReachedEndNavigationResult>());
    });
  });
}

class _FailingAvatarApi extends FakeMatrixApi {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PUT' && request.url.path.endsWith('/avatar_url')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"errcode":"M_UNKNOWN","error":"failed"}')),
        500,
      );
    }
    return super.send(request);
  }
}

class _ShowsTrialPage implements TrialInfoProvider {
  @override
  bool get shouldShowTrialPage => true;

  @override
  Future<void> setShowedTrialPage() async {}
}

class _FailingUpdater implements AccountUpdater {
  @override
  Future<void> updateProfile(Profile Function(Profile) update) async =>
      throw Exception('save failed');
}
