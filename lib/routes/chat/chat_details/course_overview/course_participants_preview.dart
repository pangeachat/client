import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_button.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';

/// The course page's Participants section: its header and, below, a single
/// left-aligned line of [ParticipantCard]s, truncated to the cards that fit
/// the available width (at most [maxParticipants]). The full wrapped list
/// (every member, invite tile) is the section's "All participants" subpage —
/// RoomParticipantsSection.
///
/// This widget owns the whole section because both of its decisions turn on
/// the same measurement — how many cards fit:
///
/// - the cards themselves are cut to that count (#8578);
/// - the header's action is "All participants" when members were truncated,
///   and the invite button when they were not (#8744). A subpage repeating
///   the same cards is not worth offering, and a section that fits every
///   member is exactly the one whose useful next step is inviting more. When
///   the button does show, invite is still one tap away — the subpage it
///   opens carries its own invite tile.
class CourseParticipantsPreview extends StatelessWidget {
  final Room room;

  /// Opens the section's "All participants" subpage.
  final VoidCallback onShowAll;

  /// Opens the invite flow.
  final VoidCallback onInvite;

  static const int maxParticipants = 8;

  static const double _spacing = 8.0;

  const CourseParticipantsPreview({
    required this.room,
    required this.onShowAll,
    required this.onInvite,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LoadParticipantsBuilder(
      room: room,
      loadProfiles: true,
      builder: (context, participantsLoader) {
        final sorted = participantsLoader.sortedParticipants;
        final originalLeaders = sorted.take(3).toList();
        final participants = [...sorted]..sort(ParticipantCard.displayCompare);
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
            final truncated = participants.length > fit;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CourseSectionHeader(
                  title: SpaceSettingsTabs.participants.title(context),
                  trailing: truncated
                      ? CourseSectionButton(
                          label: L10n.of(context).allParticipants,
                          icon: Icons.group_outlined,
                          onPressed: onShowAll,
                        )
                      : room.canInvite
                      ? FilledButton.tonalIcon(
                          onPressed: onInvite,
                          icon: const Icon(Icons.person_add_outlined, size: 16),
                          label: Text(
                            L10n.of(context).invite,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 8.0),
                Semantics(
                  label: L10n.of(
                    context,
                  ).listLabel(L10n.of(context).participant),
                  container: true,
                  child: Row(
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
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
