import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/onboarding/account_updater.dart';
import 'package:fluffychat/pangea/onboarding/avatar_provider.dart';
import 'package:fluffychat/pangea/onboarding/course_provider.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';

OnboardingStep getInitialOnboardingStep(Client client) {
  return ProfileSetupOnboardingStep(
    client: client,
    state: OnboardingStateController(
      accountUpdater: MockAccountUpdater(),
      courseProvider: MockCourseProvider(),
      avatarProvider: MockAvatarProvider(),
    ),
    maxRemainingSteps: 5,
  );
}
