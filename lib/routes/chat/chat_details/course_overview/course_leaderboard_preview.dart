import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/pangea/spaces/course_leaderboard.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_button.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_shortcut.dart';
import 'package:fluffychat/routes/chat/chat_details/leaderboard_row.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';

/// The course page's Leaderboard section (course-leaderboard.instructions.md):
/// its header, the admin line cut to the cards that fit, and the podium — the
/// top three as [LeaderboardRow]s, or a lone member over an invite row. The
/// full ranking is the section's subpage — CourseLeaderboardPage.
///
/// This widget owns the whole section because the header's "See all" turns on
/// what the subpage holds beyond the preview, and only the preview knows how
/// many admin cards fit. Invite sits beside it whenever this user may invite,
/// whether or not anything was cut (#8744): a section showing every member is
/// exactly the one whose useful next step is inviting more, and a full one
/// still is.
class CourseLeaderboardPreview extends StatelessWidget {
  final Room room;

  /// Opens the section's full subpage.
  final VoidCallback onShowAll;

  /// Opens the invite flow.
  final VoidCallback onInvite;

  static const int maxAdmins = 8;

  static const double _spacing = 8.0;

  const CourseLeaderboardPreview({
    required this.room,
    required this.onShowAll,
    required this.onInvite,
    super.key,
  });

  /// The whole admin cards that fit one line of [width]:
  /// n·width + (n−1)·spacing.
  static int adminsThatFit(double width) => width.isFinite
      ? ((width + _spacing) / (ParticipantCard.compactWidth + _spacing))
            .floor()
            .clamp(1, maxAdmins)
            .toInt()
      : maxAdmins;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return LoadParticipantsBuilder(
      room: room,
      loadProfiles: true,
      builder: (context, participantsLoader) {
        final board = participantsLoader.leaderboard(
          langCode: room.coursePlan?.l2,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final fit = adminsThatFit(constraints.maxWidth);
            final admins = board.admins.take(fit).toList();
            final subpageHasMore =
                board.admins.length > fit ||
                board.ranked.length > CourseLeaderboard.podiumSize ||
                board.pending.isNotEmpty;
            final title = SpaceSettingsTabs.participants.title(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CourseSectionHeader(
                  title: title,
                  icon: Icons.group_outlined,
                  actions: [
                    if (room.canInvite)
                      CourseSectionShortcut(
                        icon: Icons.person_add_outlined,
                        tooltip: l10n.invite,
                        onPressed: onInvite,
                      ),
                    if (subpageHasMore)
                      CourseSectionButton(section: title, onPressed: onShowAll),
                  ],
                ),
                const SizedBox(height: 8.0),
                if (participantsLoader.loading)
                  // Rows appear only once every profile is in: an order shown
                  // before that would reshuffle under the reader.
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  )
                else
                  Semantics(
                    label: l10n.listLabel(l10n.leaderboard),
                    container: true,
                    // One Tab stop for the section, the arrow keys inside it.
                    // An admin appears twice — in the line and on the podium —
                    // so the ids carry which.
                    child: RovingFocusGroup(
                      ids: [
                        for (final user in admins) 'admin:${user.id}',
                        for (final entry in board.podium)
                          'rank:${entry.user.id}',
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: _spacing,
                        children: [
                          if (admins.isNotEmpty)
                            Row(
                              spacing: _spacing,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final user in admins)
                                  ParticipantCard(
                                    user: user,
                                    room: room,
                                    rovingId: 'admin:${user.id}',
                                    showStats: false,
                                    width: ParticipantCard.compactWidth,
                                  ),
                              ],
                            ),
                          for (final entry in board.podium)
                            LeaderboardRow(
                              entry: entry,
                              room: room,
                              rovingId: 'rank:${entry.user.id}',
                            ),
                          if (board.ranked.length == 1 && room.canInvite)
                            LeaderboardInviteRow(onTap: onInvite),
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
