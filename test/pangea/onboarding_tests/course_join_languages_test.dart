import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Profile;

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';
import 'seed_language_store.dart';

/// A joined course supplies the language it teaches and its level; the
/// language the person already speaks is always the device's. See
/// `onboarding.instructions.md` § Joining a course during onboarding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late final String deviceLanguage;

  setUpAll(() async {
    await seedLanguageStore();
    deviceLanguage = LanguageService.systemLanguage?.langCodeShort ?? 'en';
  });

  setUp(() async => client = await getTestClient());
  tearDown(() => client.dispose());

  /// Joins a course with a class code and returns the step that follows.
  Future<(OnboardingNavigationController, _SavedProfile)> joinCourse({
    required String teaches,
    required String taughtIn,
  }) async {
    final saved = _SavedProfile();
    final step = CourseCodeOnboardingStep(
      client: client,
      state: OnboardingStateController(
        accountUpdater: saved,
        courseProvider: _CourseProvider(teaches: teaches, taughtIn: taughtIn),
        avatarProvider: MockAvatarProvider(),
        trialInfoProvider: MockTrialInfoProvider(),
      ),
      maxRemainingSteps: 1,
    )..setCourseCode('abc1234');
    final nav = OnboardingNavigationController(initialStep: step);
    expect(await nav.forward(), isA<SuccessNavigationResult>());
    return (nav, saved);
  }

  test('the L1 is the device language, not the course\'s', () async {
    final others = ['de', 'es', 'fr'].where((c) => c != deviceLanguage);
    final (nav, saved) = await joinCourse(
      teaches: others.first,
      taughtIn: others.last,
    );

    expect(nav.step, isA<JoinedCourseOnboardingStep>());
    final settings = saved.profile.userSettings;
    expect(settings.targetLanguage, others.first);
    expect(settings.sourceLanguage?.split('-').first, deviceLanguage);
    expect(settings.cefrLevel, LanguageLevelTypeEnum.b1);
  });

  test('a course teaching the device language asks for languages', () async {
    final other = deviceLanguage == 'de' ? 'es' : 'de';
    final (nav, saved) = await joinCourse(
      teaches: deviceLanguage,
      taughtIn: other,
    );

    expect(nav.step, isA<PickLanguageOnboardingStep>());
    expect(saved.writes, 0);
  });
}

class _SavedProfile implements AccountUpdater {
  Profile profile = Profile.emptyProfile;
  int writes = 0;

  @override
  Future<void> updateProfile(Profile Function(Profile) update) async {
    writes++;
    profile = Profile.fromAccountData(update(profile).toJson())!;
  }
}

/// A course whose content loads, teaching [teaches] and taught in [taughtIn].
class _CourseProvider extends MockCourseProvider {
  _CourseProvider({required this.teaches, required this.taughtIn});

  final String teaches;
  final String taughtIn;

  @override
  Future<CoursePlanModel?> getCourseByRoomId(String roomId) async =>
      CoursePlanModel(
        targetLanguage: teaches,
        languageOfInstructions: taughtIn,
        cefrLevel: LanguageLevelTypeEnum.b1,
        title: 'Course',
        description: 'Course for testing',
        topicIds: [],
        mediaIds: [],
        updatedAt: DateTime(2026, 5, 1),
        createdAt: DateTime(2026, 5, 1),
        uuid: 'quest-1',
      );
}
