import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';

void showSubscribedSnackbar(BuildContext context) {
  final Widget text = RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: L10n.of(context).successfullySubscribed,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.white
                : Colors.black,
          ),
        ),
        const TextSpan(text: " "),
        TextSpan(
          text: L10n.of(context).clickToManageSubscription,
          style: TextStyle(color: Theme.of(context).colorScheme.inversePrimary),
          recognizer: TapGestureRecognizer()
            ..onTap = () => context.go('/rooms/settings/subscription'),
        ),
      ],
    ),
  );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: text,
    ),
  );
}
