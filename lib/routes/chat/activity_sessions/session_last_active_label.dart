import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';

/// When an open session's members were last online, worded like the user
/// profile's presence line ("Currently active" / "Last active: 3:42 PM"),
/// from [SessionPresenceTracker] (#9333 prototype). Renders nothing when no
/// member's presence is known.
class SessionLastActiveLabel extends StatelessWidget {
  final DateTime? lastActive;

  const SessionLastActiveLabel({super.key, required this.lastActive});

  /// Within this of now reads as "Currently active".
  static const Duration _currentWindow = Duration(minutes: 1);

  @override
  Widget build(BuildContext context) {
    final lastActive = this.lastActive;
    if (lastActive == null) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final current = DateTime.now().difference(lastActive) < _currentWindow;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4.0,
      children: [
        Icon(
          Icons.schedule,
          size: 14.0,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        Text(
          current
              ? l10n.currentlyActive
              : l10n.lastActiveAgo(lastActive.localizedTimeShort(context)),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
