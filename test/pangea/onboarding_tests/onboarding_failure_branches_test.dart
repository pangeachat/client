import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide Profile;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import '../get_test_client.dart';

/// Failure branches the onboarding doc describes. See
/// `onboarding.instructions.md` § Joining a course during onboarding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    client = await getTestClient();
  });

  tearDownAll(() => client.dispose());

  test(
    'a failed save after a class-link join stays on the role page and retries from the course',
    () async {
      final courses = _LinkCourseProvider();
      // The role is saved first; the second save is the course's languages.
      final updater = _FailingUpdater(failCall: 2);
      final roleStep = UserTypeOnboardingStep(
        client: client,
        state: OnboardingStateController(
          accountUpdater: updater,
          courseProvider: courses,
          avatarProvider: MockAvatarProvider(),
          trialInfoProvider: MockTrialInfoProvider(),
        ),
        maxRemainingSteps: 4,
      )..setUserType(UserType.student);
      final nav = OnboardingNavigationController(initialStep: roleStep);

      expect(await nav.forward(), isA<ErrorNavigationResult>());
      expect(nav.step, same(roleStep));
      expect(courses.joins, 1);

      expect(await nav.forward(), isA<SuccessNavigationResult>());
      expect(nav.step, isA<JoinedCourseOnboardingStep>());
      expect(courses.joins, 1);
    },
  );
}

/// Fails only the [failCall]th profile save.
class _FailingUpdater implements AccountUpdater {
  _FailingUpdater({required this.failCall});

  final int failCall;
  int _calls = 0;

  @override
  Future<void> updateProfile(Profile Function(Profile) update) async {
    _calls++;
    if (_calls == failCall) throw Exception('save failed');
  }
}

/// A class link's code waiting at the role page, dropped once onboarding
/// clears it, as the device's copy is.
class _LinkCourseProvider extends MockCourseProvider {
  String? _cachedCode = 'abc1234';
  int joins = 0;

  @override
  String? getCachedJoinCode() => _cachedCode;

  @override
  Future<void> clearCachedJoinCode() async => _cachedCode = null;

  @override
  Future<String> joinSpaceWithCode(String code) {
    joins++;
    return super.joinSpaceWithCode(code);
  }
}
