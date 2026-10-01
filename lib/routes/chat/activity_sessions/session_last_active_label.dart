import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/elapsed_time_format.dart';

/// "Active 5m ago" for an open session, from [SessionPresenceTracker]
/// (#9333 prototype). Renders nothing when no member's presence is known.
class SessionLastActiveLabel extends StatelessWidget {
  final DateTime? lastActive;

  const SessionLastActiveLabel({super.key, required this.lastActive});

  @override
  Widget build(BuildContext context) {
    final lastActive = this.lastActive;
    if (lastActive == null) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final elapsed = DateTime.now().difference(lastActive);
    final theme = Theme.of(context);
    return Row(
      spacing: 4.0,
      children: [
        Icon(
          Icons.schedule,
          size: 14.0,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        Text(
          elapsed.inMinutes < 1
              ? l10n.sessionActiveNow
              : l10n.sessionActiveAgo(ElapsedTimeFormat.compact(elapsed, l10n)),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
