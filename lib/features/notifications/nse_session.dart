import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/platform_infos.dart';

/// Mirrors the Matrix session into the iOS App Group container, where the
/// Notification Service Extension can read it.
///
/// A backgrounded iOS device renders a notification straight from Sygnal's
/// payload without waking the app, so `pushHelper` never runs and there is no
/// local notification to attach an avatar to. The only code that can change
/// that notification is the extension — a separate process, with no access to
/// the app's own storage. Synapse media is authenticated
/// (`enable_authenticated_media: true`), so without the access token the
/// extension cannot download an avatar at all.
///
/// Both targets already declare `group.com.talktolearn.chat`, so this needs no
/// new entitlement.
class NseSession {
  static const _channel = MethodChannel('chat.pangea/nse_session');

  /// Best-effort. A failure costs a notification its avatar and nothing else,
  /// so it is logged rather than reported.
  static Future<void> store({
    required String accessToken,
    required String homeserver,
  }) async {
    if (!PlatformInfos.isIOS) return;
    await _invoke(
      'store',
      jsonEncode({
        'access_token': accessToken,
        'homeserver': homeserver,
        // Not every avatar is an mxc upload: some are plain https URLs on our
        // asset/CDN hosts (#8550). The extension needs the same allow-list.
        'allowed_image_hosts': AppConfig.allowedImageHosts.toList(),
      }),
    );
  }

  /// Called on logout: the extension must not outlive the session it holds.
  static Future<void> clear() async {
    if (!PlatformInfos.isIOS) return;
    await _invoke('clear', null);
  }

  static Future<void> _invoke(String method, String? argument) async {
    try {
      await _channel.invokeMethod<bool>(method, argument);
    } catch (e, s) {
      Logs().w('Unable to $method the notification extension session', e, s);
    }
  }
}
