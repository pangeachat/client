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
        return l10n.home;
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

  bool get addHeader => switch (this) {
    SettingsPageEnum.email => false,
    _ => true,
  };
}
