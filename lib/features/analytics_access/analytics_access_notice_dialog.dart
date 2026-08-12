import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

/// Consent notice shown when joining a course that requires analytics access.
/// Cancelling means leaving the course, so the dialog cannot be dismissed
/// without picking one of the two buttons.
class AnalyticsAccessNoticeDialog extends StatelessWidget {
  const AnalyticsAccessNoticeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Semantics(
          label: l10n.analyticsAccessNoticeTitle,
          liveRegion: true,
          container: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Semantics(
                      container: true,
                      child: Text(
                        l10n.analyticsAccessNoticeTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    container: true,
                    child: Text(
                      l10n.analyticsAccessNoticeDesc,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop<OkCancelResult>(OkCancelResult.ok),
                    child: Text(
                      l10n.shareAnalytics,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop<OkCancelResult>(OkCancelResult.cancel),
                    child: Text(l10n.leave),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
