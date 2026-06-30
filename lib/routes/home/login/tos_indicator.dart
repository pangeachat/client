import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

class TOSIndicator extends StatelessWidget {
  const TOSIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: RichText(
        textAlign: TextAlign.justify,
        text: TextSpan(
          children: [
            TextSpan(text: L10n.of(context).byUsingPangeaChat),
            TextSpan(
              text: L10n.of(context).termsAndConditions,
              style: TextStyle(
                decoration: TextDecoration.underline,
                color: theme.colorScheme.primary,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  launchUrlString(AppConfig.termsOfServiceUrl);
                },
            ),
            TextSpan(text: L10n.of(context).andCertifyIAmAtLeast13YearsOfAge),
          ],
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
