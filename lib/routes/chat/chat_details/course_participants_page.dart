import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/routes/chat/chat_details/room_participants_widget.dart';

/// The Participants section's full page ("See all",
/// course-participants.instructions.md): every member as a card, admins first
/// and pending members last, then an invite tile when this user may invite.
class CourseParticipantsPage extends StatelessWidget {
  final Room room;

  const CourseParticipantsPage({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      label: l10n.listLabel(l10n.participant),
      container: true,
      child: LoadParticipantsBuilder(
        room: room,
        builder: (context, participantsLoader) {
          if (participantsLoader.loading) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator.adaptive(),
              ),
            );
          }
          final participants = participantsLoader.courseParticipants;
          final everyone = [...participants.joined, ...participants.pending];
          // Every member is one Tab stop, the arrow keys moving through the
          // wrap in reading order; the invite tile after them is its own.
          return RovingFocusGroup(
            ids: [for (final user in everyone) user.id],
            child: Wrap(
              spacing: 8.0,
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              children: [
                for (final user in everyone)
                  ParticipantCard(
                    user: user,
                    room: room,
                    rovingId: user.id,
                    showStats: false,
                  ),
                ParticipantsInviteTile(room: room),
              ],
            ),
          );
        },
      ),
    );
  }
}
