import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/hover_builder.dart';

/// The full participant list: every member as a [ParticipantCard] in a
/// centered wrap, with a trailing invite tile. The course page's Participants
/// section renders a single-line preview instead — CourseParticipantsPreview.
class RoomParticipantsSection extends StatelessWidget {
  final Room room;

  const RoomParticipantsSection({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: L10n.of(context).listLabel(L10n.of(context).participant),
      container: true,
      child: LoadParticipantsBuilder(
        room: room,
        loadProfiles: true,
        builder: (context, participantsLoader) {
          final participants = participantsLoader.sortedParticipants;
          final originalLeaders = participants.take(3).toList();
          participants.sort(ParticipantCard.displayCompare);

          if (room.showActivityChatUI) {
            participants.removeWhere((u) => u.id == BotName.byEnvironment);
          }

          return Wrap(
            spacing: 8.0,
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            children: [
              ...participants.map(
                (user) => ParticipantCard(
                  user: user,
                  room: room,
                  gradient: ParticipantCard.leaderboardGradientFor(
                    user,
                    originalLeaders,
                    hasLevel:
                        participantsLoader
                            .getAnalyticsProfile(user.id)
                            ?.level !=
                        null,
                  ),
                ),
              ),
              _InviteTile(room: room),
            ],
          );
        },
      ),
    );
  }
}

/// The wrap's trailing invite tile, sized like a member card. Hidden when the
/// user can't invite (or in a DM).
class _InviteTile extends StatelessWidget {
  final Room room;

  const _InviteTile({required this.room});

  @override
  Widget build(BuildContext context) {
    if (!room.canInvite || room.isDirectChat) return const SizedBox();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => NavigationUtil.goToSpaceRoute(room.id, [
          'details',
          'invite',
        ], context),
        child: HoverBuilder(
          builder: (context, hovered) {
            return Container(
              decoration: BoxDecoration(
                color: hovered
                    ? Theme.of(context).colorScheme.primary.withAlpha(50)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              width: ParticipantCard.width,
              child: Semantics(
                container: true,
                child: Column(
                  spacing: 4.0,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Icon(Icons.person_add_outlined, size: 50.0),
                    ),
                    Text(
                      L10n.of(context).invite,
                      style: const TextStyle(fontSize: 16.0),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
