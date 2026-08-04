import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The preset Pangea avatars hosted on the client assets bucket
/// (avatar_1.png .. avatar_5.png). Single source of truth for the URL
/// scheme used by onboarding, the random-avatar provider, and the
/// profile-settings preset picker.
abstract class PresetAvatars {
  static const int count = 5;

  /// [index] is 1-based, matching the asset filenames.
  static String urlString(int index) =>
      "${AppConfig.assetsBaseURL}/avatar_$index.png";

  /// [index] is 1-based, matching the asset filenames.
  static Uri url(int index) => Uri.parse(urlString(index));

  static List<Uri> get all => List.generate(count, (index) => url(index + 1));

  /// Accessibility description for a preset; [index] is 0-based,
  /// matching positions in [all].
  static String description(L10n l10n, int index) {
    switch (index) {
      case 0:
        return l10n.dinoAvatarLabel;
      case 1:
        return l10n.bearAvatarLabel;
      case 2:
        return l10n.squidAvatarLabel;
      case 3:
        return l10n.cartoonAvatarLabel;
      case 4:
        return l10n.robotAvatarLabel;
      default:
        return l10n.defaultOption;
    }
  }
}
