import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_button.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_shortcut.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';

/// The course page's Participants section
/// (course-participants.instructions.md): its header and one line of
/// [ParticipantCard]s, cut to the cards that fit. The full list is the
/// section's subpage — CourseParticipantsPage.
///
/// This widget owns the whole section because the header's "See all" turns on
/// what the subpage holds beyond the line, and only this widget knows how many
/// cards fit. Invite sits beside it whenever this user may invite, whether or
/// not anything was cut (#8744): a section showing every member is exactly the
/// one whose useful next step is inviting more, and a full one still is.
class CourseParticipantsPreview extends StatelessWidget {
  final Room room;

  /// Opens the section's full subpage.
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

  /// The whole cards that fit one line of [width]: n·width + (n−1)·spacing.
  static int participantsThatFit(double width) => width.isFinite
      ? ((width + _spacing) / (ParticipantCard.width + _spacing))
            .floor()
            .clamp(1, maxParticipants)
            .toInt()
      : maxParticipants;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return LoadParticipantsBuilder(
      room: room,
      builder: (context, participantsLoader) {
        final participants = participantsLoader.courseParticipants;
        return LayoutBuilder(
          builder: (context, constraints) {
            final fit = participantsThatFit(constraints.maxWidth);
            final joined = participants.joined;
            final shown = joined.take(fit).toList();
            final subpageHasMore =
                joined.length > fit || participants.pending.isNotEmpty;
            final title = SpaceSettingsTabs.participants.title(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CourseSectionHeader(
                  title: title,
                  icon: Icons.group_outlined,
                  actions: [
                    if (room.canInviteMembers)
                      CourseSectionShortcut(
                        icon: Icons.person_add_outlined,
                        label: l10n.invite,
                        showLabel: false,
                        onPressed: onInvite,
                      ),
                    if (subpageHasMore)
                      CourseSectionButton(section: title, onPressed: onShowAll),
                  ],
                ),
                const SizedBox(height: 8.0),
                if (participantsLoader.loading)
                  // A partial member list would reorder as the rest arrived.
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  )
                else
                  Semantics(
                    label: l10n.listLabel(l10n.participant),
                    container: true,
                    // One Tab stop for the line, the arrow keys inside it.
                    child: RovingFocusGroup(
                      ids: [for (final user in shown) user.id],
                      child: Row(
                        spacing: _spacing,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final user in shown)
                            ParticipantCard(
                              user: user,
                              room: room,
                              rovingId: user.id,
                              showStats: false,
                            ),
                        ],
                      ),
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
