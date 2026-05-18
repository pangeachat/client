import 'dart:typed_data';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/user_type_onboarding_step.dart';

class ProfileSetupOnboardingStep extends OnboardingStep {
  ProfileSetupOnboardingStep({
    required super.client,
    required super.state,
    required super.maxRemainingSteps,
  }) {
    _avatarUrl = state.avatarProvider.getRandomAvatarUrl();
  }

  String? _displayName;
  Uint8List? _avatarBytes;
  Uri? _avatarUrl;

  String? get displayName => _displayName;
  Uint8List? get avatarBytes => _avatarBytes;
  Uri? get avatarUrl => _avatarUrl;

  void setDisplayName(String name) => _displayName = name;

  void setAvatarBytes(Uint8List bytes) {
    _avatarBytes = bytes;
    _avatarUrl = null;
  }

  void setAvatarUrl(Uri url) {
    _avatarUrl = url;
    _avatarBytes = null;
  }

  @override
  Future<OnboardingStep?> execute() async {
    Uri? avatarUrl = this.avatarUrl;
    final avatarBytes = this.avatarBytes;
    if (avatarBytes != null && avatarUrl == null) {
      try {
        avatarUrl = await client.uploadContent(avatarBytes);
      } catch (e, s) {
        ErrorHandler.logError(e: e, s: s, data: {});
      }
    }

    final userID = client.userID;
    final currentProfile = await client.fetchOwnProfile();

    try {
      if (avatarUrl != null && avatarUrl != currentProfile.avatarUrl) {
        await client.setProfileField(userID!, 'avatar_url', {
          'avatar_url': avatarUrl.toString(),
        });
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
    }

    try {
      final displayName = this.displayName;
      if (displayName != null && displayName != currentProfile.displayName) {
        await client.setProfileField(userID!, 'displayname', {
          'displayname': displayName,
        });
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
