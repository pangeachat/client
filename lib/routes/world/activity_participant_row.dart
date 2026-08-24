import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/user_profile_builder.dart';

/// The Joinable / Ongoing-Pending participant row: an optional leading icon
/// (door vs hourglass) followed by filled/unfilled avatar circles, one per role
/// — world-map.instructions.md, "Pin state".
///
/// Participants are bare Matrix ids: each circle fetches its own owner's
/// profile ([UserProfileAvatar]). Callers pass ids and nothing else — a name or
/// avatar resolved upstream from room state is wrong for the row's main case, a
/// session the learner has not joined and so has no member events for (#8192).

class ActivityParticipantRow extends StatelessWidget {
  static const int defaultMaxVisible = 5;
  final IconData? icon;
  final Color accent;
  final List<String> participants;
  final int openSlots;
  final double avatarSize;

  /// The most avatars + empty seats to draw; defaults to the shared
  /// [defaultMaxVisible] so the map and the card cap identically.
  final int maxVisible;

  const ActivityParticipantRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.participants,
    required this.openSlots,
    this.avatarSize = 28,
    this.maxVisible = defaultMaxVisible,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty && openSlots <= 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Semantics(
      label: L10n.of(context).participantRowLabel(
        participants.length,
        participants.length + openSlots,
      ),
      container: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
            ],
            for (final userId in participants.take(maxVisible)) ...[
              UserProfileAvatar(userId: userId, size: avatarSize),
              const SizedBox(width: 4),
            ],
            // An open seat, matching the activity-lobby's open-role look
            // (ActivityParticipantIndicator)
            for (int i = 0; i < openSlots.clamp(0, maxVisible); i++) ...[
              CircleAvatar(
                radius: avatarSize / 2,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person,
                  size: avatarSize * 0.57,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}
