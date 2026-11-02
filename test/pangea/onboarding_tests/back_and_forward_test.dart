import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/custom_course_request_model.dart';
import 'package:fluffychat/routes/onboarding/custom_course_response_model.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/custom_course_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/custom_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';

/// Going back and then forward again keeps every page's choices and repeats
/// no join or course request that nothing changed. See
/// `onboarding.instructions.md` § What onboarding reads and saves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // BotFace falls back to a CachedNetworkImage, whose cache manager needs
    // path_provider; stub the channel to a temp dir.
    final tempDir = Directory.systemTemp.createTempSync('back_and_forward');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    client = await getTestClient();
  });

  tearDownAll(() => client.dispose());

  OnboardingStateController newState(_CountingCourseProvider courses) =>
      OnboardingStateController(
        accountUpdater: MockAccountUpdater(),
        courseProvider: courses,
        avatarProvider: MockAvatarProvider(),
        trialInfoProvider: MockTrialInfoProvider(),
      );

  OnboardingStateController teacherReadyToRequest(
    _CountingCourseProvider courses,
  ) => newState(courses)
    ..setUserType(UserType.teacher)
    ..setBaseLanguage(LanguageModel(langCode: 'en', displayName: 'English'))
    ..setTargetLanguage(LanguageModel(langCode: 'es', displayName: 'Spanish'))
    ..setLanguageLevel(LanguageLevelTypeEnum.a2);

  CustomCourseOnboardingStep requestStep(OnboardingStateController state) =>
      CustomCourseOnboardingStep(
        client: client,
        state: state,
        maxRemainingSteps: 0,
      );

  group('course request', () {
    test(
      'answers outlive the page and an unchanged request is sent once',
      () async {
        final courses = _CountingCourseProvider();
        final state = teacherReadyToRequest(courses);

        requestStep(state)
          ..setName('Ana')
          ..setInstitution('Lincoln High')
          ..setGoals('Textbook: Avancemos 1');
        await requestStep(state).execute();
        expect(courses.requests, 1);

        // Back past the page and forward again builds a new page.
        final again = requestStep(state);
        expect(again.enableGoForward, isTrue);
        await again.execute();
        expect(courses.requests, 1);

        again.setGoals('Textbook: Avancemos 2');
        await again.execute();
        expect(courses.requests, 2);
      },
    );

    testWidgets('a new page shows the answers already typed', (tester) async {
      final state = teacherReadyToRequest(_CountingCourseProvider())
        ..setCourseRequestName('Ana')
        ..setCourseRequestInstitution('Lincoln High')
        ..setCourseRequestGoals('Textbook: Avancemos 1');

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: CustomCourseStepView(
              step: requestStep(state),
              loading: false,
              error: null,
              hasNextStep: true,
              forward: () {},
              skip: () {},
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Lincoln High'), findsOneWidget);
      expect(find.text('Textbook: Avancemos 1'), findsOneWidget);
    });
  });

  test('the class-code page does not join again with the same code', () async {
    final courses = _CountingCourseProvider();
    final codeStep = CourseCodeOnboardingStep(
      client: client,
      state: newState(courses),
      maxRemainingSteps: 1,
    )..setCourseCode('abc1234');
    final nav = OnboardingNavigationController(initialStep: codeStep);

    expect(await nav.forward(), isA<SuccessNavigationResult>());
    expect(nav.back(), isA<SuccessNavigationResult>());
    expect(nav.step, same(codeStep));
    expect(await nav.forward(), isA<SuccessNavigationResult>());

    expect(courses.joins, 1);
    expect(nav.step, isA<JoinedCourseOnboardingStep>());
  });

  test(
    'back to the role page after a class-link join continues from that course',
    () async {
      final courses = _CountingCourseProvider(cachedCode: 'abc1234');
      final roleStep = UserTypeOnboardingStep(
        client: client,
        state: newState(courses),
        maxRemainingSteps: 4,
      )..setUserType(UserType.student);
      final nav = OnboardingNavigationController(initialStep: roleStep);

      expect(await nav.forward(), isA<SuccessNavigationResult>());
      expect(nav.step, isA<JoinedCourseOnboardingStep>());
      expect(courses.cachedCode, isNull);

      expect(nav.back(), isA<SuccessNavigationResult>());
      expect(await nav.forward(), isA<SuccessNavigationResult>());

      expect(nav.step, isA<JoinedCourseOnboardingStep>());
      expect(courses.joins, 1);
    },
  );
}

/// Counts joins and course requests, and drops a class link's code once
/// onboarding clears it, as the device's copy does.
class _CountingCourseProvider extends MockCourseProvider {
  _CountingCourseProvider({this.cachedCode});

  String? cachedCode;
  int joins = 0;
  int requests = 0;

  @override
  String? getCachedJoinCode() => cachedCode;

  @override
  Future<void> clearCachedJoinCode() async => cachedCode = null;

  @override
  Future<String> joinSpaceWithCode(String code) {
    joins++;
    return super.joinSpaceWithCode(code);
  }

  @override
  Future<Result<CustomCourseResponseModel>> requestCustomCourse(
    CustomCourseRequestModel request,
  ) {
    requests++;
    return super.requestCustomCourse(request);
  }
}
