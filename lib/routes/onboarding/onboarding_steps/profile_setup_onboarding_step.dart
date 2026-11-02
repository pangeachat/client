import 'dart:typed_data';

import 'package:fluffychat/features/user/own_profile_client_extension.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';

class ProfileSetupOnboardingStep extends OnboardingStep {
  ProfileSetupOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  });

  void setDisplayName(String name) => state.setDisplayName(name);

  void setAvatarBytes(Uint8List bytes) =>
      state.setAvatarInfo(AvatarInfo(avatarBytes: bytes));

  void setAvatarUrl(Uri url) => state.setAvatarInfo(AvatarInfo(avatarUrl: url));

  @override
  Future<OnboardingStep?> execute() async {
    Uri? avatarUrl = state.avatarInfo?.avatarUrl;
    final avatarBytes = state.avatarInfo?.avatarBytes;
    if (avatarBytes != null && avatarUrl == null) {
      try {
        avatarUrl = await client.uploadContent(avatarBytes);
      } catch (e, s) {
        ErrorHandler.logError(e: e, s: s, data: {});
      }
    }

    final currentProfile = await client.fetchOwnProfile();

    // Next can come before the page has loaded the profile and picked an
    // avatar; an account with none still gets a random preset.
    if (avatarUrl == null &&
        avatarBytes == null &&
        currentProfile.avatarUrl == null) {
      avatarUrl = state.avatarProvider.getRandomAvatarUrl();
      state.setAvatarInfo(AvatarInfo(avatarUrl: avatarUrl));
    }

    try {
      if (avatarUrl != null && avatarUrl != currentProfile.avatarUrl) {
        await client.setOwnAvatarUrl(avatarUrl);
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    }

    try {
      final displayName = state.displayName;
      if (displayName != null && displayName != currentProfile.displayName) {
        await client.setOwnDisplayName(displayName);
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    }

    return UserTypeOnboardingStep(
      client: client,
      state: state,
      maxRemainingSteps: 4,
    );
  }

  @override
  OnboardingStep? skip() => UserTypeOnboardingStep(
    client: client,
    state: state,
    maxRemainingSteps: 4,
  );
}
