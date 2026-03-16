import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:app_settings/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/l10n/l10n.dart';

class EnableAutocorrectDialog extends StatelessWidget {
  const EnableAutocorrectDialog({super.key});

  @override
  Widget build(BuildContext context) {
    String title;
    String? steps;
    String? description;
    String buttonText;
    VoidCallback buttonAction;

    if (kIsWeb) {
      title = L10n.of(context).autocorrectNotAvailable; // Default
      buttonText = L10n.of(context).ok;
      buttonAction = Navigator.of(context).pop;
    } else if (Platform.isIOS) {
      title = L10n.of(context).enableAutocorrectPopupTitle;
      steps = L10n.of(context).enableAutocorrectPopupSteps;
      description = L10n.of(context).enableAutocorrectPopupDescription;
      buttonText = L10n.of(context).settings;
      buttonAction = AppSettings.openAppSettings;
    } else {
      title = L10n.of(context).downloadGboardTitle;
      steps = L10n.of(context).downloadGboardSteps;
      description = L10n.of(context).downloadGboardDescription;
      buttonText = L10n.of(context).downloadGboard;
      buttonAction = () {
        launchUrl(
          Uri.parse(
            'https://play.google.com/store/apps/details?id=com.google.android.inputmethod.latin',
          ),
        );
      };
    }

    return AlertDialog.adaptive(
      title: Text(L10n.of(context).enableAutocorrectWarning),
      content: SingleChildScrollView(
        child: Column(
          spacing: 8.0,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(title),
            if (steps != null) Text(steps, textAlign: TextAlign.start),
            if (description != null) Text(description),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(L10n.of(context).close),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(onPressed: buttonAction, child: Text(buttonText)),
      ],
    );
  }
}
