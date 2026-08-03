import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:android_intent_plus/android_intent.dart';
import 'package:app_settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// Which remedy to offer when no known-good voice exists for the L2.
/// See message-read-aloud.instructions.md, "Enabling requires a qualifying
/// voice".
enum ReadAloudVoiceAdvice {
  /// Non-Chromium desktop browser: Chrome/Edge bundle their own good voices.
  desktopWeb,

  /// Any mobile browser: every iOS browser is WebKit and shares Safari's
  /// voices, so the app — not another browser — is the upgrade path.
  mobileWeb,

  /// Apple native: the user can download an Enhanced/Premium voice in system
  /// settings.
  ios,

  /// Android native: install voice data for the device TTS engine.
  android;

  static ReadAloudVoiceAdvice pick({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) {
      return platform == TargetPlatform.iOS ||
              platform == TargetPlatform.android
          ? mobileWeb
          : desktopWeb;
    }
    if (platform == TargetPlatform.android) return android;
    // iOS, and any other Apple native build: the Spoken Content settings
    // advice applies there too.
    return ios;
  }
}

/// Shown when the user turns on auto-read-aloud but the current platform has
/// no known-good voice for their target language. The toggle stays off; this
/// dialog explains why and links to where a qualifying voice can be found.
class ReadAloudVoiceDialog extends StatelessWidget {
  /// Display name of the learner's target language, for the dialog copy.
  final String language;

  const ReadAloudVoiceDialog({super.key, required this.language});

  static const String _chromeUrl = 'https://www.google.com/chrome/';
  static const String _iosAppStoreUrl =
      'https://apps.apple.com/app/id1445118630';

  @override
  Widget build(BuildContext context) {
    final advice = ReadAloudVoiceAdvice.pick(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    switch (advice) {
      case ReadAloudVoiceAdvice.desktopWeb:
        return _buildDialog(
          context,
          body: [Text(L10n.of(context).readAloudNoVoiceDesktopWeb(language))],
          actionTitle: L10n.of(context).readAloudGetChrome,
          onAction: () => launchUrl(Uri.parse(_chromeUrl)),
        );
      case ReadAloudVoiceAdvice.mobileWeb:
        return _buildDialog(
          context,
          body: [Text(L10n.of(context).readAloudNoVoiceMobileWeb(language))],
          actionTitle: L10n.of(context).readAloudGetApp,
          onAction: () => launchUrl(
            Uri.parse(
              defaultTargetPlatform == TargetPlatform.iOS
                  ? _iosAppStoreUrl
                  : AppConfig.androidUpdateURL,
            ),
          ),
        );
      case ReadAloudVoiceAdvice.ios:
        return _buildDialog(
          context,
          body: [
            Text(L10n.of(context).readAloudNoVoiceIOS(language)),
            Text(
              L10n.of(context).readAloudNoVoiceIOSSteps(language),
              textAlign: TextAlign.start,
            ),
          ],
          actionTitle: L10n.of(context).settings,
          onAction: AppSettings.openAppSettings,
        );
      case ReadAloudVoiceAdvice.android:
        return _buildDialog(
          context,
          body: [Text(L10n.of(context).readAloudNoVoiceAndroid(language))],
          actionTitle: L10n.of(context).readAloudOpenVoiceSettings,
          onAction: _openAndroidVoiceSettings,
        );
    }
  }

  /// The voice-data installer for the default TTS engine is the exact
  /// destination; older or de-Googled devices may not resolve it, so fall
  /// back to the system TTS settings screen.
  static Future<void> _openAndroidVoiceSettings() async {
    try {
      await const AndroidIntent(
        action: 'android.speech.tts.engine.INSTALL_TTS_DATA',
      ).launch();
    } catch (_) {
      await const AndroidIntent(
        action: 'com.android.settings.TTS_SETTINGS',
      ).launch();
    }
  }

  Widget _buildDialog(
    BuildContext context, {
    required List<Widget> body,
    required String actionTitle,
    required VoidCallback onAction,
  }) {
    return AlertDialog.adaptive(
      title: Text(L10n.of(context).readAloudNoVoiceTitle(language)),
      content: SingleChildScrollView(
        child: Column(
          spacing: 8.0,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: body,
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).close),
        ),
        AdaptiveDialogAction(
          onPressed: () {
            onAction();
            Navigator.of(context).pop();
          },
          child: Text(actionTitle),
        ),
      ],
    );
  }
}
