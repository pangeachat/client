import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/users/course_member_stats.dart';
import 'package:fluffychat/widgets/users/level_display_name.dart';
import 'package:fluffychat/widgets/users/member_actions_popup_menu_button.dart';

/// One participant's member card: avatar (with the top-3 leaderboard ring),
/// the permission/membership badge across the avatar's top edge, name, and the
/// member's stars and level in the course's language. A space with no course
/// language recorded — anything created before it was written to room state —
/// falls back to the learner chip ([LevelDisplayName]), which shows their own
/// language pair. Tapping the avatar opens the member actions menu. Shared by the full participant list
/// (RoomParticipantsSection) and the course page's Participants preview.
class ParticipantCard extends StatelessWidget {
  static const double width = 100.0;

  final User user;
  final Room room;

  /// The top-3 leaderboard ring, resolved by the surrounding list via
  /// [leaderboardGradientFor].
  final LinearGradient? gradient;

  const ParticipantCard({
    required this.user,
    required this.room,
    this.gradient,
    super.key,
  });

  /// Display order within a participants list: the bot last, then admins,
  /// then joined, invited, and knocking members.
  static int displayCompare(User a, User b) {
    final aIsBot = a.id == BotName.byEnvironment;
    final bIsBot = b.id == BotName.byEnvironment;
    if (aIsBot != bIsBot) {
      return aIsBot ? 1 : -1;
    }

    int rankOf(User p) {
      if (p.powerLevel == 100) return 0;
      switch (p.membership) {
        case Membership.join:
          return 1;
        case Membership.invite:
          return 2;
        case Membership.knock:
          return 3;
        default:
          return 4;
      }
    }

    // Deterministic within a rank: List.sort is not stable, and callers hand
    // in a level-sorted list whose order the tie-break must not scramble.
    final byRank = rankOf(a).compareTo(rankOf(b));
    return byRank != 0 ? byRank : a.id.compareTo(b.id);
  }

  /// The ring for [user]: its position among [leaders] (the level-sorted top
  /// three), unless the user is the bot or has no level to rank by.
  static LinearGradient? leaderboardGradientFor(
    BuildContext context,
    User user,
    List<User> leaders, {
    required bool hasLevel,
  }) {
    final leaderIndex = leaders.indexOf(user);
    if (leaderIndex == -1) return null;
    if (user.id == BotName.byEnvironment || !hasLevel) return null;
    return leaderIndex.leaderboardGradient(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final courseLanguage = room.coursePlan?.l2;

    final badge = switch (user.membership) {
      Membership.invite => _ParticipantBadge(
        label: L10n.of(context).invited,
        color: theme.colorScheme.secondaryContainer,
        onColor: theme.colorScheme.onSecondaryContainer,
      ),
      Membership.knock => _ParticipantBadge(
        label: L10n.of(context).knocking,
        color: theme.colorScheme.secondaryContainer,
        onColor: theme.colorScheme.onSecondaryContainer,
      ),
      _ when user.powerLevel >= SpaceConstants.powerLevelOfAdmin =>
        _ParticipantBadge(
          label: L10n.of(context).admin,
          color: theme.pangea.goldFixedDim,
          onColor: theme.pangea.onGoldFixed,
        ),
      _ when user.powerLevel >= 50 => _ParticipantBadge(
        label: L10n.of(context).moderator,
        color: theme.pangea.goldContainer,
        onColor: theme.pangea.onGoldContainer,
      ),
      _ => null,
    };

    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: SizedBox(
          width: width,
          child: Opacity(
            opacity: user.membership == Membership.join ? 1.0 : 0.5,
            child: Column(
              spacing: 4.0,
              children: [
                Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (gradient != null)
                      ExcludeSemantics(
                        child: CircleAvatar(
                          radius: width / 2,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: gradient,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: width, width: width),
                    Builder(
                      builder: (context) {
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => showMemberActionsPopupMenu(
                              context: context,
                              user: user,
                              room: room,
                            ),
                            child: Center(
                              child: ExcludeSemantics(
                                child: Avatar(
                                  mxContent: user.avatarUrl,
                                  name: user.localizedDisplayname(
                                    L10n.of(context),
                                  ),
                                  size: width - 6.0,
                                  presenceUserId: user.id,
                                  presenceOffset: const Offset(0, 0),
                                  presenceSize: 18.0,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Straddles the avatar's top edge (#9109), rising into the
                    // card's top padding instead of reserving a row below the
                    // stats that most cards leave empty. Taps fall through to
                    // the avatar beneath.
                    if (badge != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: FractionalTranslation(
                          translation: const Offset(0, -0.5),
                          child: Center(child: IgnorePointer(child: badge)),
                        ),
                      ),
                  ],
                ),
                Text(
                  user.localizedDisplayname(L10n.of(context)),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Container(
                  height: 20.0,
                  alignment: Alignment.center,
                  child: courseLanguage != null
                      ? CourseMemberStats(
                          userId: user.id,
                          langCode: courseLanguage,
                          textStyle: theme.textTheme.labelSmall,
                        )
                      : LevelDisplayName(
                          userId: user.id,
                          textStyle: theme.textTheme.labelSmall,
                          showFlags: false,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A permission or membership label on a [ParticipantCard]. Ringed in the
/// surface color, like the avatar's presence dot, so it separates from the
/// avatar image or leaderboard ring it overlaps.
class _ParticipantBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color onColor;

  const _ParticipantBadge({
    required this.label,
    required this.color,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: theme.colorScheme.surface, width: 2),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(color: onColor),
      ),
    );
  }
}
