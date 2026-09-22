import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/widgets/hover_builder.dart';

/// A chat's full participant list: every member as a [ParticipantCard] in a
/// centered wrap, with a trailing invite tile. A course ranks its members
/// instead — CourseLeaderboardPage.
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

          // The members are one Tab stop, the arrow keys moving through the
          // wrap in reading order; the invite tile after them is its own.
          return RovingFocusGroup(
            ids: [for (final user in participants) user.id],
            child: Wrap(
              spacing: 8.0,
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              children: [
                ...participants.map(
                  (user) => ParticipantCard(
                    user: user,
                    room: room,
                    rovingId: user.id,
                    gradient: ParticipantCard.leaderboardGradientFor(
                      context,
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
            ),
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

    // Focusable, named and ringed, where a bare GestureDetector took a mouse
    // only (#9154). The tile keeps its own hover fill, so the ink's is off.
    return FocusRingTapTarget(
      onTap: () => NavigationUtil.goToSpaceRoute(room.id, [
        'details',
        'invite',
      ], context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8.0)),
      ),
      hoverColor: Colors.transparent,
      label: L10n.of(context).invite,
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
            width: ParticipantCard.defaultWidth,
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
    );
  }
}
