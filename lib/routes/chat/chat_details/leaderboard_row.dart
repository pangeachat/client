import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/pangea/common/widgets/role_badge.dart';
import 'package:fluffychat/pangea/common/widgets/roving_focus_group.dart';
import 'package:fluffychat/pangea/extensions/localized_display_name_extension.dart';
import 'package:fluffychat/pangea/spaces/course_leaderboard.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/users/course_member_stats.dart';
import 'package:fluffychat/widgets/users/member_actions_popup_menu_button.dart';

/// A podium row — one of the top three (course-leaderboard.instructions.md):
/// the medal ring and rank badge around the avatar, a crown on first place,
/// the name with any role badge, then the stars and level, on a row washed in
/// the medal's colour. The whole row opens the member actions menu.
class LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final Room room;

  /// This row's id in the enclosing [RovingFocusGroup]; null outside one.
  final String? rovingId;

  static const double avatarSize = 64.0;

  const LeaderboardRow({
    required this.entry,
    required this.room,
    this.rovingId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return _MemberTarget(
      user: entry.user,
      room: room,
      rovingId: rovingId,
      fill:
          entry.medal?.rowFill(theme) ?? theme.colorScheme.surfaceContainerHigh,
      // Over a medal wash a single-colour ring can vanish into the gold.
      twoToneRing: true,
      child: Row(
        spacing: 12.0,
        children: [
          _RankedAvatar(entry: entry, size: avatarSize),
          Expanded(
            child: _NameAndBadge(user: entry.user, style: textStyle),
          ),
          _Stats(entry: entry, textStyle: textStyle, iconSize: 24.0),
        ],
      ),
    );
  }
}

/// A compact tile for fourth place onward: the rank as a leading number, the
/// avatar, then the name and role badge over the stars. Sits in the full
/// page's one- or two-column grid.
class LeaderboardTile extends StatelessWidget {
  final LeaderboardEntry entry;
  final Room room;
  final String? rovingId;

  static const double avatarSize = 44.0;

  const LeaderboardTile({
    required this.entry,
    required this.room,
    this.rovingId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _MemberTarget(
      user: entry.user,
      room: room,
      rovingId: rovingId,
      fill: Colors.transparent,
      twoToneRing: false,
      child: Row(
        spacing: 8.0,
        children: [
          // The number is the rank: announced as such, ahead of the name.
          Semantics(
            label: L10n.of(context).leaderboardRank(entry.rank),
            child: ExcludeSemantics(
              child: SizedBox(
                width: 28.0,
                child: Text(
                  '${entry.rank}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          _RankedAvatar(entry: entry, size: avatarSize),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2.0,
              children: [
                _NameAndBadge(
                  user: entry.user,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _Stats(
                    entry: entry,
                    textStyle: theme.textTheme.labelMedium,
                    iconSize: 16.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Invite row: second place on a leaderboard of one, and the full page's
/// last row. Shaped like a podium row so the leaderboard says what the next
/// step is in its own terms.
class LeaderboardInviteRow extends StatelessWidget {
  final VoidCallback onTap;

  const LeaderboardInviteRow({required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return FocusRingTapTarget(
      onTap: onTap,
      shape: _MemberTarget.shape,
      label: l10n.invite,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: _MemberTarget.borderRadius,
        ),
        padding: _MemberTarget.padding,
        child: Row(
          spacing: 12.0,
          children: [
            const SizedBox(
              width: LeaderboardRow.avatarSize,
              height: LeaderboardRow.avatarSize,
              child: Icon(Icons.person_add_outlined, size: 32.0),
            ),
            Text(
              l10n.invite,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tappable, focusable shell of a row or tile: one node — a button named
/// by everything inside it, the level shield's own node included — whose
/// whole area opens the member actions menu.
class _MemberTarget extends StatelessWidget {
  final User user;
  final Room room;
  final String? rovingId;
  final Color fill;
  final bool twoToneRing;
  final Widget child;

  static final BorderRadius borderRadius = BorderRadius.circular(
    AppConfig.borderRadius,
  );
  static final OutlinedBorder shape = RoundedRectangleBorder(
    borderRadius: borderRadius,
  );
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 12.0,
    vertical: 8.0,
  );

  const _MemberTarget({
    required this.user,
    required this.room,
    required this.rovingId,
    required this.fill,
    required this.twoToneRing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final rovingId = this.rovingId;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Builder(
          builder: (context) => FocusRingTapTarget(
            onTap: () => showMemberActionsPopupMenu(
              context: context,
              user: user,
              room: room,
            ),
            focusNode: rovingId == null
                ? null
                : RovingFocusGroup.nodeOf(context, rovingId),
            shape: shape,
            twoToneRing: twoToneRing,
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: borderRadius,
              ),
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The avatar with, on the podium, its medal ring, rank badge at the top-left
/// and — for first place — a crown over the top edge. Off the podium it is
/// the plain avatar: the tile's leading number already says the rank.
class _RankedAvatar extends StatelessWidget {
  final LeaderboardEntry entry;
  final double size;

  static const double _ringWidth = 3.0;

  const _RankedAvatar({required this.entry, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = entry.medal;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (medal != null)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: medal.ring(theme),
              ),
            ),
          // The name is read from the row's text, not the avatar.
          ExcludeSemantics(
            child: Avatar(
              mxContent: entry.user.avatarUrl,
              name: entry.user.localizedDisplayname(L10n.of(context)),
              size: medal == null ? size : size - 2 * _ringWidth,
              presenceUserId: entry.user.id,
              presenceOffset: Offset.zero,
              presenceSize: 14.0,
            ),
          ),
          if (medal != null)
            Positioned(
              top: -4.0,
              left: -4.0,
              child: Semantics(
                label: L10n.of(context).leaderboardRank(entry.rank),
                child: ExcludeSemantics(
                  child: _RankBadge(rank: entry.rank, medal: medal),
                ),
              ),
            ),
          if (medal == LeaderboardMedal.gold)
            Positioned(
              top: -12.0,
              child: ExcludeSemantics(
                child: Icon(
                  Symbols.crown,
                  fill: 1.0,
                  size: 20.0,
                  color: theme.pangea.goldGraphic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The rank number on a medal-coloured disc, ringed in the surface colour so
/// it separates from the ring and avatar it overlaps — the role badge's own
/// treatment.
class _RankBadge extends StatelessWidget {
  final int rank;
  final LeaderboardMedal medal;

  const _RankBadge({required this.rank, required this.medal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 22.0,
      height: 22.0,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: medal.color(theme),
        border: Border.all(color: theme.colorScheme.surface, width: 2.0),
      ),
      child: Text(
        '$rank',
        style: theme.textTheme.labelSmall?.copyWith(
          color: medal.onColor(theme),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _NameAndBadge extends StatelessWidget {
  final User user;
  final TextStyle? style;

  const _NameAndBadge({required this.user, required this.style});

  @override
  Widget build(BuildContext context) {
    final badge = RoleBadgeType.forMember(user);
    return Row(
      spacing: 6.0,
      children: [
        Flexible(
          child: Text(
            user.localizedDisplayname(L10n.of(context)),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (badge != null) RoleBadge(badge),
      ],
    );
  }
}

/// The member's stars and level in the language they were ranked on; nothing
/// when no language is known, since there is nothing to attribute a count to.
class _Stats extends StatelessWidget {
  final LeaderboardEntry entry;
  final TextStyle? textStyle;
  final double iconSize;

  const _Stats({
    required this.entry,
    required this.textStyle,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final language = entry.language;
    if (language == null) return const SizedBox.shrink();
    return MemberStatsRow(
      stars: entry.stars,
      level: entry.level,
      langCode: language,
      textStyle: textStyle,
      iconSize: iconSize,
      showZeroStars: true,
    );
  }
}
