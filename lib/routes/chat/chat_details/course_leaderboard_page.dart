import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/chat_details/leaderboard_row.dart';
import 'package:fluffychat/routes/chat/chat_details/participant_card.dart';
import 'package:fluffychat/utils/navigation_util.dart';

/// The Leaderboard's full page ("See all", course-leaderboard.instructions.md):
/// the admin line wrapped rather than cut, the podium, fourth place onward as
/// [LeaderboardTile]s in one or two columns, the pending members as cards, and
/// an invite row when this user may invite. The course page's section shows a
/// cut of this — CourseLeaderboardPreview.
class CourseLeaderboardPage extends StatelessWidget {
  final Room room;

  /// The width from which the tiles sit in two columns.
  static const double twoColumnMinWidth = 500.0;

  static const double _spacing = 8.0;

  const CourseLeaderboardPage({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      label: l10n.listLabel(l10n.leaderboard),
      container: true,
      child: LoadParticipantsBuilder(
        room: room,
        loadProfiles: true,
        builder: (context, participantsLoader) {
          if (participantsLoader.loading) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator.adaptive(),
              ),
            );
          }
          final board = participantsLoader.leaderboard(
            langCode: room.coursePlan?.l2,
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= twoColumnMinWidth ? 2 : 1;
              // Floored so two tiles and their gap never round past the width.
              final tileWidth =
                  ((constraints.maxWidth - _spacing * (columns - 1)) / columns)
                      .floorToDouble();
              // Every member is one Tab stop, the arrow keys moving down the
              // page in reading order; the invite row after them is its own.
              // An admin appears twice, so the ids carry which.
              return RovingFocusGroup(
                ids: [
                  for (final user in board.admins) 'admin:${user.id}',
                  for (final entry in board.ranked) 'rank:${entry.user.id}',
                  for (final user in board.pending) 'pending:${user.id}',
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: _spacing,
                  children: [
                    if (board.admins.isNotEmpty) ...[
                      Wrap(
                        spacing: _spacing,
                        children: [
                          for (final user in board.admins)
                            ParticipantCard(
                              user: user,
                              room: room,
                              rovingId: 'admin:${user.id}',
                              showStats: false,
                              width: ParticipantCard.compactWidth,
                            ),
                        ],
                      ),
                      const Divider(),
                    ],
                    for (final entry in board.podium)
                      LeaderboardRow(
                        entry: entry,
                        room: room,
                        rovingId: 'rank:${entry.user.id}',
                      ),
                    if (board.rest.isNotEmpty)
                      Wrap(
                        spacing: _spacing,
                        runSpacing: _spacing,
                        children: [
                          for (final entry in board.rest)
                            SizedBox(
                              width: tileWidth,
                              child: LeaderboardTile(
                                entry: entry,
                                room: room,
                                rovingId: 'rank:${entry.user.id}',
                              ),
                            ),
                        ],
                      ),
                    if (board.pending.isNotEmpty)
                      Wrap(
                        spacing: _spacing,
                        children: [
                          for (final user in board.pending)
                            ParticipantCard(
                              user: user,
                              room: room,
                              rovingId: 'pending:${user.id}',
                              showStats: false,
                              width: ParticipantCard.compactWidth,
                            ),
                        ],
                      ),
                    if (room.canInvite)
                      LeaderboardInviteRow(
                        onTap: () => NavigationUtil.goToSpaceRoute(room.id, [
                          'details',
                          'invite',
                        ], context),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
