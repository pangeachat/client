import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Read-only review of a **completed** activity session, shown as a right-column
/// panel (`review:` token). It renders the finished-activity summary — the
/// overall recap plus each participant's feedback card — straight from
/// `room.activitySummaryByL1` (Matrix room state). It deliberately uses **no**
/// [ChatController] and opens **no** timeline, so it can coexist with a live
/// session (see the one-live-session rule in `routing.instructions.md`).
///
/// Privacy: other participants' cards show only when the viewer was a
/// participant themselves (so they already saw these in the live wrap-up) or can
/// administrate the room; otherwise just the viewer's own card. Mirrors the
/// intent of `ActivitySummaryStatus.canView`.
class CompletedActivityReviewPanel extends StatelessWidget {
  /// Full Matrix room id of the completed session.
  final String roomId;

  const CompletedActivityReviewPanel({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId);

    final summary = room?.activitySummaryByL1?.summary;
    if (room == null ||
        (room.activitySummaryByL1?.hasError ?? true) ||
        summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.oopsSomethingWentWrong,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final myId = client.userID;
    final viewerParticipated =
        myId != null && summary.userSummary(myId) != null;
    // ownPowerLevel >= 50 is the moderator/admin proxy; refine to the exact
    // course-admin check if one is introduced.
    final canSeeAll = viewerParticipated || room.ownPowerLevel >= 50;
    final participants = canSeeAll
        ? summary.participants
        : summary.participants.where((p) => p.participantId == myId).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.activityFinishedMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(summary.summary, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        for (final p in participants) ...[
          _ParticipantCard(room: room, participant: p),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  final Room room;
  final ParticipantSummaryModel participant;

  const _ParticipantCard({required this.room, required this.participant});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final user = room
        .getParticipants()
        .firstWhereOrNull((u) => u.id == participant.participantId);
    final displayName = user?.calcDisplayname() ??
        participant.participantId.localpart ??
        participant.participantId;
    final assignedRole = (room.assignedRoles ?? {})
        .values
        .firstWhereOrNull((r) => r.userId == participant.participantId);
    final roleLabel = assignedRole?.role ?? l10n.participant;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: Color.alphaBlend(
          Theme.of(context).colorScheme.surface.withAlpha(70),
          AppConfig.gold,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(
                name: participant.participantId.localpart,
                mxContent: user?.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '$roleLabel | $displayName',
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            participant.displayFeedback(displayName),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(participant.cefrLevel, style: const TextStyle(fontSize: 14)),
              for (final superlative in participant.superlatives)
                Text(superlative, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }
}
