import 'dart:typed_data';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/random_avatar_provider.dart';

class ProfileSetupOnboardingStep extends OnboardingStep {
  ProfileSetupOnboardingStep({
    required super.client,
    super.stepIndex = 1,
    super.totalSteps = 6,
    String? displayName,
    Uint8List? avatarBytes,
    Uri? avatarUrl,
  }) {
    _displayName = displayName;
    _avatarBytes = avatarBytes;
    if (_avatarBytes == null) {
      _avatarUrl = avatarUrl;
    }
  }

  RandomAvatarProvider? _avatarProvider;

  String? _displayName;
  Uint8List? _avatarBytes;
  Uri? _avatarUrl;

  String? get displayName => _displayName;
  Uint8List? get avatarBytes => _avatarBytes;
  Uri? get avatarUrl => _avatarUrl;

  List<Uri> get avatarOptions => _avatarProvider?.avatarOptions ?? [];

  void setInititalAvatar(RandomAvatarProvider avatarProvider) {
    _avatarProvider = avatarProvider;
    if (_avatarBytes == null && _avatarUrl == null) {
      _avatarUrl = avatarProvider.getRandomAvatarUrl();
    }
  }

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
  OnboardingStep? get nextStep =>
      UserTypeOnboardingStep(prevStep: this, client: client);

  @override
  Future<void> execute() async {
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

    if (avatarUrl != null && avatarUrl != currentProfile.avatarUrl) {
      await client.setProfileField(userID!, 'avatar_url', {
        'avatar_url': avatarUrl.toString(),
      });
    }

    final displayName = this.displayName;
    if (displayName != null && displayName != currentProfile.displayName) {
      await client.setProfileField(userID!, 'displayname', {
        'displayname': displayName,
      });
    }
  }
}
