import 'package:flutter/material.dart';

/// A short note with one action, shown in place of media that can't show:
/// a video or image the network blocks, or a video YouTube won't play here.
///
/// With [fill] the note takes the media's whole space on a muted band, so the
/// layout around it keeps its shape; without it the note stands alone.
class MediaUnavailableNote extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final bool fill;

  /// For a note that replaces a control the learner may have had focused.
  /// Autofocus yields to anything else that has focus.
  final bool autofocusAction;

  const MediaUnavailableNote({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.fill = false,
    this.autofocusAction = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        // Wraps rather than overflowing in a small image cell.
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            Text(message),
            TextButton(
              autofocus: autofocusAction,
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
    if (!fill) return note;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(child: note),
    );
  }
}
