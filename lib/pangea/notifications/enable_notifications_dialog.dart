import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class EnableNotificationsDialog extends StatelessWidget {
  const EnableNotificationsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 32.0,
                bottom: 24.0,
              ),
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.enableNotificationsTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    l10n.enableNotificationsDesc,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop<OkCancelResult>(OkCancelResult.ok),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.enableNotifications,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHigh,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop<OkCancelResult>(OkCancelResult.cancel),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.skipForNow,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(180),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Close button
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(
                  context,
                ).pop<OkCancelResult>(OkCancelResult.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
