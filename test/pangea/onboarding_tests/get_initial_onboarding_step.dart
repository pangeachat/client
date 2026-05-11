import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';

OnboardingStep getInitialOnboardingStep(
  Client client,
  Uri Function() getRandomAvatarUrl,
) {
  final step = ProfileSetupOnboardingStep(
    displayName: "test_user_1",
    client: client,
    maxTotalSteps: 6,
  );
  step.setup(getRandomAvatarUrl);
  return step;
}
