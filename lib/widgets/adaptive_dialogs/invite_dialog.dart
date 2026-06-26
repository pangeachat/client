import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// One full-width action button in an [showInviteDialog].
class InviteDialogAction<T> {
  final String label;
  final T value;
  final bool destructive;
  const InviteDialogAction({
    required this.label,
    required this.value,
    this.destructive = false,
  });
}

/// Incoming-invite confirmation popup.
///
/// Replaces `AlertDialog.adaptive`, whose Cupertino card is not hit-opaque over
/// its padding, so a tap on the card interior fell through to the dismiss
/// barrier and closed the popup (#7284). A plain `Material` card is opaque to
/// *paint* but not to *hit-testing* (empty card areas with no child don't
/// absorb taps), so the card is wrapped in an explicit
/// `GestureDetector(HitTestBehavior.opaque)` that swallows every interior tap as
/// a no-op. Tapping the dimmed surround outside the card still dismisses
/// (returns null). Buttons are full-width and stacked.
Future<T?> showInviteDialog<T>(
  BuildContext context, {
  required String title,
  required String message,
  required List<InviteDialogAction<T>> actions,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final theme = Theme.of(context);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Material(
              elevation: theme.dialogTheme.elevation ?? 4,
              shadowColor: theme.dialogTheme.shadowColor,
              color:
                  theme.dialogTheme.backgroundColor ??
                  theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              clipBehavior: Clip.hardEdge,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    for (final action in actions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.surfaceBright,
                              foregroundColor: action.destructive
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppConfig.borderRadius,
                                ),
                              ),
                            ),
                            onPressed: () =>
                                Navigator.of(context).pop(action.value),
                            child: Text(action.label),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
