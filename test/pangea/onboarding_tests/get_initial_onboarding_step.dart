import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/random_avatar_provider.dart';

OnboardingStep getInitialOnboardingStep(
  RandomAvatarProvider avatarProvider,
  Client client,
) {
  final step = ProfileSetupOnboardingStep(
    displayName: "test_user_1",
    client: client,
  );
  step.setInititalAvatar(avatarProvider);
  return step;
}
