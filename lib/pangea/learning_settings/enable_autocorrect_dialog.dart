import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:app_settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

class EnableAutocorrectDialog extends StatelessWidget {
  const EnableAutocorrectDialog({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return WebEnableAutocorrectDialog();
    }

    if (Platform.isIOS) {
      return IOSEnableAutocorrectDialog();
    }

    return AndroidEnableAutocorrectDialog();
  }
}

class WebEnableAutocorrectDialog extends StatelessWidget {
  const WebEnableAutocorrectDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(L10n.of(context).enableAutocorrectWarning),
      content: SingleChildScrollView(
        child: Column(
          spacing: 8.0,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [Text(L10n.of(context).autocorrectNotAvailable)],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(L10n.of(context).close),
        ),
      ],
    );
  }
}

class IOSEnableAutocorrectDialog extends StatelessWidget {
  const IOSEnableAutocorrectDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(L10n.of(context).enableAutocorrectWarning),
      content: SingleChildScrollView(
        child: Column(
          spacing: 8.0,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(L10n.of(context).enableAutocorrectPopupTitle),
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

class AndroidEnableAutocorrectDialog extends StatelessWidget {
  const AndroidEnableAutocorrectDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(L10n.of(context).enableAutocorrectWarning),
      content: SingleChildScrollView(
        child: Column(
          spacing: 8.0,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(L10n.of(context).downloadGboardTitle),
            Text(
              L10n.of(context).downloadGboardSteps,
              textAlign: TextAlign.start,
            ),
            Text(L10n.of(context).downloadGboardDescription),
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
            launchUrl(
              Uri.parse(
                'https://play.google.com/store/apps/details?id=com.google.android.inputmethod.latin',
              ),
            );
            Navigator.of(context).pop(true);
          },
          child: Text(L10n.of(context).downloadGboard),
        ),
      ],
    );
  }
}
