import 'package:flutter/material.dart';

import 'package:fluffychat/features/navigation/token_params/settings_token.dart';
import 'package:fluffychat/routes/profile/user_home_page.dart';
import 'package:fluffychat/routes/settings/settings.dart';
import 'package:fluffychat/routes/settings/settings_chat/settings_chat.dart';
import 'package:fluffychat/routes/settings/settings_device/device_settings.dart';
import 'package:fluffychat/routes/settings/settings_learning/settings_learning.dart';
import 'package:fluffychat/routes/settings/settings_notifications/settings_notifications.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_3pid/settings_3pid.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_ignore_list/settings_ignore_list.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_password/settings_password.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_security.dart';
import 'package:fluffychat/routes/settings/settings_style/settings_style.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription.dart';
import 'package:fluffychat/routes/settings/settings_subscription/subscription_history.dart';

/// The body of the right-column **settings panel** (world_v2): the profile +
/// settings tree, hosted in one panel instead of the retired route-driven
/// column. The active page is the `settings` token's param ([subPath]); an
/// empty param is the menu, and a sub-page is reached by a *push* (the menu row
/// sets the param) with the panel's back arrow popping it. The panel chrome
/// (close on the menu, back on a sub-page) is supplied by [WorkspaceRightPanel].
/// See `routing.instructions.md`.
class RightPanelSettingsSubpage extends StatelessWidget {
  /// The settings sub-page id from the token param, e.g. `learning`,
  /// `security`, `security/password`, `profile/edit`. Null/empty is the menu.
  final SettingsTokenParam? param;
  final Widget closeButton;
  const RightPanelSettingsSubpage({
    super.key,
    this.param,
    required this.closeButton,
  });

  @override
  Widget build(BuildContext context) {
    // The ignore-list can open pre-seeded with a user to block (from a chat's
    // context menu or a profile dialog). The seed rides the token param as a
    // 3rd segment — `security/ignorelist/<userid>` — restoring the seed the old
    // route dropped (a redirect can't carry `extra:`). See routing.instructions.md.
    final sub = param?.subpage;
    if (sub != null && sub.startsWith('security/ignorelist')) {
      final parts = sub.split('/');
      return SettingsIgnoreList(
        initialUserId: parts.length > 2 ? parts.sublist(2).join('/') : null,
      );
    }

    switch (sub) {
      case null:
      case '':
        // The menu (profile header + settings list). It has no app bar of its
        // own, so the panel card header is its only chrome.
        return const Settings();
      case 'learning':
        return const SettingsLearning();
      case 'style':
        return const SettingsStyle();
      case 'notifications':
        return const SettingsNotifications();
      case 'devices':
        return const DevicesSettings();
      case 'chat':
        return const SettingsChat();
      case 'subscription':
        return SettingsSubscription(closeButton: closeButton);
      case 'subscription/history':
        return SubscriptionHistory(closeButton: closeButton);
      case 'security':
        return const SettingsSecurity();
      case 'security/password':
        return const SettingsPassword();
      case 'security/3pid':
        return Settings3Pid(closeButton: closeButton);
      case 'profile':
      // A bare `profile` detail (e.g. the legacy `/settings/profile` path, which
      // the redirect maps to `settingspage:profile`) is the profile itself, NOT
      // the menu: without this it fell through to `default → Settings()`, which
      // re-rendered the menu a second time beside the always-present `settings`
      // master — the "duplicate settings menu" bug. See routing.instructions.md.
      case 'profile/edit':
        return UserHomePage();
      default:
        // An unknown sub-page (a stale link) degrades to the menu rather than
        // a blank panel.
        return const Settings();
    }
  }
}
