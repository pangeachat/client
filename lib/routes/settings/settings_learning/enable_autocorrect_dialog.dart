import 'dart:io';

import 'package:flutter/material.dart';

import 'package:android_intent_plus/android_intent.dart';
import 'package:app_settings/app_settings.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// Platform-specific instructions for enabling device autocorrect. Only shown
/// on mobile — on web the autocorrect toggle is disabled entirely (see
/// AutocorrectSettingsTile).
///
/// Reached from two places with different framing. The autocorrect settings
/// toggle keeps each platform's default [title], which warns that the setting
/// depends on a target-language keyboard. The composer's "Add keyboard"
/// prompt passes its own — the learner tapped it to add a keyboard, so a
/// warning that one is required reads as a non sequitur (#8804).
class EnableAutocorrectDialog extends StatelessWidget {
  final String? title;

  const EnableAutocorrectDialog({super.key, this.title});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return IOSEnableAutocorrectDialog(title: title);
    }

    return AndroidEnableAutocorrectDialog(title: title);
  }
}

class IOSEnableAutocorrectDialog extends StatelessWidget {
  final String? title;

  const IOSEnableAutocorrectDialog({super.key, this.title});

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(title ?? L10n.of(context).enableAutocorrectWarning),
      content: SingleChildScrollView(
        child: Column(
          spacing: 8.0,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(L10n.of(context).enableAutocorrectPopupPathIntro),
            Text(
              L10n.of(context).enableAutocorrectPopupSteps,
              textAlign: TextAlign.start,
            ),
            Text(L10n.of(context).enableAutocorrectPopupDescription),
          ],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(L10n.of(context).close),
        ),
        AdaptiveDialogAction(
          onPressed: () {
            AppSettings.openAppSettings();
            Navigator.of(context).pop(true);
          },
          child: Text(L10n.of(context).settings),
        ),
      ],
    );
  }
}

/// On Android the composer passes the target language to the keyboard
/// (`hintLocales`), so no manual keyboard switch is needed — the dialog just
/// explains that, and its action takes the learner straight to the system's
/// keyboard-management screen for the case where the keyboard has no pack for
/// the language, per target-language-keyboard.instructions.md.
class AndroidEnableAutocorrectDialog extends StatelessWidget {
  final String? title;

  const AndroidEnableAutocorrectDialog({super.key, this.title});

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(title ?? L10n.of(context).autocorrectAndroidDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          spacing: 8.0,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(L10n.of(context).autocorrectAndroidDialogBody),
            Text(L10n.of(context).autocorrectAndroidFallbackTitle),
          ],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(L10n.of(context).close),
        ),
        AdaptiveDialogAction(
          onPressed: () {
            _openKeyboardSettings();
            Navigator.of(context).pop(true);
          },
          child: Text(L10n.of(context).openKeyboardSettings),
        ),
      ],
    );
  }

  /// `ACTION_INPUT_METHOD_SETTINGS` opens the system's keyboard-management
  /// screen directly, where the learner can enable a keyboard or add a
  /// language pack to one they already have. Android's own docs warn a
  /// matching activity may not exist on some builds, so fall back to the
  /// app's general settings screen.
  static Future<void> _openKeyboardSettings() async {
    try {
      await const AndroidIntent(
        action: 'android.settings.INPUT_METHOD_SETTINGS',
      ).launch();
    } catch (_) {
      await AppSettings.openAppSettings();
    }
  }
}
