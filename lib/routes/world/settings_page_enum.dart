import 'package:fluffychat/l10n/l10n.dart';

enum SettingsPageEnum {
  profile,
  learning,
  style,
  notifications,
  devices,
  chat,
  subscription,
  security,
  ignore,
  email,
  password,
  menu;

  static SettingsPageEnum fromString(String? path) {
    if (path != null && path.contains('security/ignorelist')) {
      return SettingsPageEnum.ignore;
    }
    // The subscription family is one page family with several leaves
    // (`subscription/history`, `/discount`, `/selected`); they all render their
    // own app bar, so every leaf must resolve here rather than falling through
    // to `menu` — a leaf that resolved to `menu` would take the shared header
    // AND draw its own (double header).
    if (path != null && path.startsWith('subscription')) {
      return SettingsPageEnum.subscription;
    }
    switch (path) {
      case 'learning':
        return SettingsPageEnum.learning;
      case 'style':
        return SettingsPageEnum.style;
      case 'notifications':
        return SettingsPageEnum.notifications;
      case 'devices':
        return SettingsPageEnum.devices;
      case 'chat':
        return SettingsPageEnum.chat;
      case 'subscription':
        return SettingsPageEnum.subscription;
      case 'security':
        return SettingsPageEnum.security;
      case 'security/password':
        return SettingsPageEnum.password;
      case 'security/3pid':
        return SettingsPageEnum.email;
      case 'profile':
      case 'profile/edit':
        return SettingsPageEnum.profile;
      default:
        return SettingsPageEnum.menu;
    }
  }

  String title(L10n l10n) {
    switch (this) {
      case SettingsPageEnum.profile:
        return l10n.editProfile;
      case SettingsPageEnum.learning:
        return l10n.learningSettings;
      case SettingsPageEnum.style:
        return l10n.changeTheme;
      case SettingsPageEnum.notifications:
        return l10n.notifications;
      case SettingsPageEnum.devices:
        return l10n.devices;
      case SettingsPageEnum.chat:
        return l10n.chat;
      case SettingsPageEnum.subscription:
        return l10n.subscriptionManagement;
      case SettingsPageEnum.security:
        return l10n.security;
      case SettingsPageEnum.ignore:
        return l10n.blockedUsers;
      case SettingsPageEnum.email:
        return l10n.changeEmail;
      case SettingsPageEnum.password:
        return l10n.changePassword;
      case SettingsPageEnum.menu:
        return l10n.settings;
    }
  }

  /// Whether the panel wraps this page in the shared [PanelCardWithHeader]
  /// chrome (X/back + title). **The wrapper is the default**: a settings view
  /// that renders no chrome of its own would otherwise have no title and no way
  /// out. Opt out ONLY for a page that renders its own header and takes the
  /// panel's `closeButton` — otherwise it draws two. See
  /// routing.instructions.md § Closing a panel.
  bool get addHeader => switch (this) {
    // Own PanelHeader with a trailing add-email action.
    SettingsPageEnum.email => false,
    // The subscription family: each leaf builds its own AppBar so it can carry
    // a leaf-specific title (e.g. the selected plan) the token can't express.
    SettingsPageEnum.subscription => false,
    _ => true,
  };
}
