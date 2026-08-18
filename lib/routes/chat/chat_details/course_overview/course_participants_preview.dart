import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';

/// The course page's Participants section highlight: a single left-aligned
/// line of [ParticipantCard]s, truncated to the cards that fit the available
/// width (at most [maxParticipants]). No invite tile — the section header
/// carries the invite button. The full wrapped list (every member, invite
/// tile) is the section's "All participants" subpage —
/// RoomParticipantsSection.
class CourseParticipantsPreview extends StatelessWidget {
  final Room room;

  static const int maxParticipants = 8;

  static const double _spacing = 8.0;

  const CourseParticipantsPreview({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: L10n.of(context).listLabel(L10n.of(context).participant),
      container: true,
      child: LoadParticipantsBuilder(
        room: room,
        loadProfiles: true,
        builder: (context, participantsLoader) {
          final sorted = participantsLoader.sortedParticipants;
          final originalLeaders = sorted.take(3).toList();
          final participants = [...sorted]
            ..sort(ParticipantCard.displayCompare);
          return LayoutBuilder(
            builder: (context, constraints) {
              // The whole cards that fit the line: n·width + (n−1)·spacing.
              final fit = constraints.maxWidth.isFinite
                  ? ((constraints.maxWidth + _spacing) /
                            (ParticipantCard.width + _spacing))
                        .floor()
                        .clamp(1, maxParticipants)
                        .toInt()
                  : maxParticipants;
              return Row(
                spacing: _spacing,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: participants
                    .take(fit)
                    .map(
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
                    )
                    .toList(),
              );
            },
          );
        },
      ),
    );
  }
}
