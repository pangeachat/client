import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// Says why a message could not be sent: too large for the server, or refused
/// by moderation.
class SendRefusedDialog extends StatelessWidget {
  final String message;

  const SendRefusedDialog({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Icon(
        Icons.error_outline_outlined,
        color: Theme.of(context).colorScheme.error,
        size: 48,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Text(message),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).close),
        ),
      ],
    );
  }
}
