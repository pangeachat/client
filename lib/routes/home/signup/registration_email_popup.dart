import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class RegistrationEmailPopup extends StatelessWidget {
  final Future<void> Function() onResendEmail;
  const RegistrationEmailPopup({super.key, required this.onResendEmail});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Text(
                      l10n.weSentYouAnEmail,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    l10n.clickOnEmailLinkDesc,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop<OkCancelResult>(OkCancelResult.ok),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.iHaveClickedOnLink,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    spacing: 4.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          l10n.didntReceiveEmail,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      TextButton(
                        onPressed: onResendEmail,
                        child: Text(l10n.resend),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Close button
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, size: 18),
                splashRadius: 18,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
