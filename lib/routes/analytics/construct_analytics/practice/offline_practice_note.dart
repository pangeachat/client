import 'package:flutter/material.dart';

import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// A quiet line, shown only while the app cannot reach Pangea, saying that
/// practice keeps working and when its results upload. See
/// practice-exercises.instructions.md, "Offline Practice".
class OfflinePracticeNote extends StatelessWidget {
  final bool _completed;

  /// Space around the note while it shows. The note takes no space while it
  /// is hidden, so a gap kept here instead of in the parent leaves no hole.
  final EdgeInsets padding;

  /// Under the progress bar while a session runs.
  const OfflinePracticeNote.session({this.padding = EdgeInsets.zero, super.key})
    : _completed = false;

  /// On the completion view.
  const OfflinePracticeNote.completed({
    this.padding = EdgeInsets.zero,
    super.key,
  }) : _completed = true;

  @override
  Widget build(BuildContext context) {
    final controller = ConnectionStatusController.instance;
    return ListenableBuilder(
      listenable: controller.reachability,
      builder: (context, _) {
        if (!controller.cannotReachPangea) return const SizedBox.shrink();

        final l10n = L10n.of(context);
        final theme = Theme.of(context);
        final color = theme.colorScheme.onSurfaceVariant;
        final style = _completed
            ? theme.textTheme.bodyMedium
            : theme.textTheme.bodySmall;
        return Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6.0,
            children: [
              Icon(
                _completed
                    ? Icons.cloud_upload_outlined
                    : Icons.cloud_off_outlined,
                size: _completed ? 20.0 : 16.0,
                color: color,
              ),
              Flexible(
                child: Text(
                  _completed
                      ? l10n.offlinePracticeSavedNote
                      : l10n.offlinePracticeNote,
                  style: style?.copyWith(color: color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
