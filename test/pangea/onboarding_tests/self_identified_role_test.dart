import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Profile, Result;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_client_extension.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/user_type_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

/// #9445 — the onboarding teacher/student choice is stored in the `profile`
/// account-data event as `user_settings.self_identified_role`, where outreach
/// reads it to tell self-identified teachers from learners.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roleKey = UserConstants.selfIdentifiedRole;

  /// Another device's profile: everything the role write must leave alone.
  Map<String, Object?> existingProfile() => {
    UserConstants.userSettings: {
      'target_language': 'es',
      'source_language': 'en',
      UserConstants.cefrLevel: 'B1',
      UserConstants.userCountry: 'Chile',
    },
    UserConstants.toolSettings: {'audioWords': false, 'listenFirst': true},
    UserConstants.instructionsSettings: <String, Object?>{},
  };

  setUp(ErrorHandler.resetReportedOnceKeysForTest);

  group('UserSettings.selfIdentifiedRole', () {
    test('stores each choice as the value outreach reads', () {
      expect(UserSettings(selfIdentifiedRole: UserType.teacher).toJson(), {
        ...UserSettings().toJson(),
        roleKey: 'teacher',
      });
      expect(
        UserSettings(selfIdentifiedRole: UserType.student).toJson()[roleKey],
        'student',
      );
    });

    test('reads each choice back', () {
      for (final role in UserType.values) {
        final stored = UserSettings(selfIdentifiedRole: role).toJson();
        expect(UserSettings.fromJson(stored).selfIdentifiedRole, role);
      }
    });

    test('an account that never chose stays unspecified, with no field', () {
      final legacy = UserSettings.fromJson({'target_language': 'es'});
      expect(legacy.selfIdentifiedRole, isNull);
      expect(legacy.toJson().containsKey(roleKey), isFalse);
    });

    test('an unrecognized value is reported and read as neither role', () {
      for (final value in ['admin', 42]) {
        ErrorHandler.resetReportedOnceKeysForTest();
        expect(
          UserSettings.fromJson({roleKey: value}).selfIdentifiedRole,
          null,
        );
        expect(
          ErrorHandler.reportedOnceKeysForTest,
          contains('unrecognized_$roleKey'),
        );
      }
    });

    test('setting the role leaves the rest of the profile unchanged', () {
      final profile = Profile.fromAccountData(existingProfile())!;
      final updated = profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          selfIdentifiedRole: UserType.teacher,
        ),
      );

      final before = profile.toJson();
      final after = updated.toJson();
      expect(
        after[UserConstants.toolSettings],
        before[UserConstants.toolSettings],
      );
      expect(
        after[UserConstants.instructionsSettings],
        before[UserConstants.instructionsSettings],
      );
      expect(after[UserConstants.userSettings], {
        ...before[UserConstants.userSettings] as Map<String, dynamic>,
        roleKey: 'teacher',
      });
    });
  });

  group('onboarding role step', () {
    late Client client;

    setUp(() async {
      client = await getTestClient();
    });
    tearDown(() => client.dispose());

    OnboardingNavigationController navigation(
      _StoredProfileUpdater updater, {
      CourseProvider? courseProvider,
    }) => OnboardingNavigationController(
      initialStep: ProfileSetupOnboardingStep(
        client: client,
        state: OnboardingStateController(
          accountUpdater: updater,
          courseProvider: courseProvider ?? MockCourseProvider(),
          avatarProvider: MockAvatarProvider(),
          trialInfoProvider: MockTrialInfoProvider(),
        ),
        maxRemainingSteps: 5,
      ),
    );

    Future<OnboardingNavigationController> atRoleStep(
      _StoredProfileUpdater updater, {
      CourseProvider? courseProvider,
    }) async {
      final nav = navigation(updater, courseProvider: courseProvider);
      expect(await nav.forward(), isA<SuccessNavigationResult>());
      expect(nav.step, isA<UserTypeOnboardingStep>());
      return nav;
    }

    for (final role in UserType.values) {
      test(
        'choosing ${role.name} stores it and keeps the other settings',
        () async {
          final updater = _StoredProfileUpdater(
            Profile.fromAccountData(existingProfile())!,
          );
          final nav = await atRoleStep(updater);

          (nav.step as UserTypeOnboardingStep).setUserType(role);
          expect(await nav.forward(), isA<SuccessNavigationResult>());
          expect(nav.step, isA<CourseCodeOnboardingStep>());

          final settings = updater.stored.userSettings;
          expect(settings.selfIdentifiedRole, role);
          expect(settings.targetLanguage, 'es');
          expect(settings.cefrLevel, LanguageLevelTypeEnum.b1);
          expect(settings.country, 'Chile');
          expect(updater.stored.toolSettings.listenFirst, isTrue);
        },
      );
    }

    test(
      'a failed write keeps the step, skips the course join, and can be retried',
      () async {
        final courseProvider = _CachedCodeCourseProvider();
        final updater = _StoredProfileUpdater(Profile.emptyProfile)
          ..failWith = Exception('write failed');
        final nav = await atRoleStep(updater, courseProvider: courseProvider);
        (nav.step as UserTypeOnboardingStep).setUserType(UserType.teacher);

        final failed = await nav.forward();
        expect(failed, isA<ErrorNavigationResult>());
        expect(nav.step, isA<UserTypeOnboardingStep>());
        expect(updater.stored.userSettings.selfIdentifiedRole, isNull);
        expect(courseProvider.joinAttempts, 0);

        updater.failWith = null;
        courseProvider.cachedCode = null;
        expect(await nav.forward(), isA<SuccessNavigationResult>());
        expect(
          updater.stored.userSettings.selfIdentifiedRole,
          UserType.teacher,
        );
      },
    );

    test('a restarted onboarding resumes with the stored choice', () {
      final step = UserTypeOnboardingStep(
        client: client,
        state: OnboardingStateController(
          accountUpdater: MockAccountUpdater(),
          courseProvider: MockCourseProvider(),
          avatarProvider: MockAvatarProvider(),
          trialInfoProvider: MockTrialInfoProvider(),
          userType: UserType.teacher,
        ),
        maxRemainingSteps: 3,
      );
      expect(step.state.userType, UserType.teacher);
      expect(step.enableGoForward, isTrue);
    });
  });

  group('Client.selfIdentifiedRole', () {
    test('reads only its own account', () async {
      final teacher = await getTestClient(name: 'teacher_account');
      final other = await getTestClient(name: 'other_account');
      addTearDown(teacher.dispose);
      addTearDown(other.dispose);

      teacher.accountData[UserConstants.userProfile] = BasicEvent(
        type: UserConstants.userProfile,
        content: {
          UserConstants.userSettings: {roleKey: 'teacher'},
        },
      );
      other.accountData[UserConstants.userProfile] = BasicEvent(
        type: UserConstants.userProfile,
        content: existingProfile(),
      );

      expect(teacher.selfIdentifiedRole, UserType.teacher);
      expect(other.selfIdentifiedRole, isNull);
    });

    test('is unspecified for an account with no profile yet', () async {
      final fresh = await getTestClient(name: 'fresh_account');
      addTearDown(fresh.dispose);
      fresh.accountData.remove(UserConstants.userProfile);
      expect(fresh.selfIdentifiedRole, isNull);
    });
  });

  group('UserTypeStepView', () {
    late Client client;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      client = await getTestClient(name: 'view_client');
      MatrixState.pangeaController = PangeaController(
        matrixState: _FakeMatrixState(client),
      );
    });
    tearDownAll(() => client.dispose());

    Future<void> pumpView(
      WidgetTester tester, {
      UserType? storedRole,
      Object? error,
    }) async {
      final state = OnboardingStateController(
        accountUpdater: MockAccountUpdater(),
        courseProvider: MockCourseProvider(),
        avatarProvider: MockAvatarProvider(),
        trialInfoProvider: MockTrialInfoProvider(),
        userType: storedRole,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: UserTypeStepView(
              step: UserTypeOnboardingStep(
                client: client,
                state: state,
                maxRemainingSteps: 3,
              ),
              loading: false,
              error: error,
              hasNextStep: true,
              forward: () {},
            ),
          ),
        ),
      );
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
    }

    testWidgets('a stored choice is shown already selected', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpView(tester, storedRole: UserType.teacher);

      expect(
        tester.getSemantics(find.widgetWithText(ElevatedButton, 'Teach')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.widgetWithText(ElevatedButton, 'Learn')),
        isSemantics(isSelected: false, hasSelectedState: true),
      );
      semantics.dispose();
    });

    testWidgets('a failed save is shown above the button', (tester) async {
      await pumpView(tester);
      expect(find.byType(ErrorIndicator), findsNothing);

      await pumpView(tester, error: Exception('write failed'));
      expect(find.byType(ErrorIndicator), findsOneWidget);
      expect(
        find.textContaining('something went wrong', findRichText: true),
        findsOneWidget,
      );
    });
  });
}

/// Applies each update to a stored profile through a full serialization
/// round trip, the way account data stores and returns it.
class _StoredProfileUpdater implements AccountUpdater {
  _StoredProfileUpdater(this.stored);

  Profile stored;
  Object? failWith;

  @override
  Future<void> updateProfile(Profile Function(Profile) update) async {
    final error = failWith;
    if (error != null) throw error;
    stored = Profile.fromAccountData(update(stored).toJson())!;
  }
}

/// A class link's join code waiting to be redeemed at the role step.
class _CachedCodeCourseProvider extends MockCourseProvider {
  String? cachedCode = 'abc123';
  int joinAttempts = 0;

  @override
  String? getCachedJoinCode() => cachedCode;

  @override
  Future<String> joinSpaceWithCode(String code) {
    joinAttempts++;
    return super.joinSpaceWithCode(code);
  }
}

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}
