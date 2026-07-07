import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';

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
            ..onTap = () => context.go(
              WorkspaceNav.openSettings(
                GoRouterState.of(context).uri,
                subpage: 'subscription',
              ),
            ),
        ),
      ],
    ),
  );
  ScaffoldMessenger.of(context).showSnackBarAnnounced(SnackBar(content: text));
}
