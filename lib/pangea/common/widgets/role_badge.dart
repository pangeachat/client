import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/l10n/l10n.dart';

enum RoleBadgeType {
  invited,
  knocking,
  admin,
  moderator;

  String label(L10n l10n) => switch (this) {
    RoleBadgeType.invited => l10n.invited,
    RoleBadgeType.knocking => l10n.knocking,
    RoleBadgeType.admin => l10n.admin,
    RoleBadgeType.moderator => l10n.moderator,
  };

  Color color(ThemeData theme) => switch (this) {
    RoleBadgeType.invited ||
    RoleBadgeType.knocking => theme.colorScheme.secondaryContainer,
    RoleBadgeType.admin => theme.pangea.goldFixedDim,
    RoleBadgeType.moderator => theme.pangea.goldContainer,
  };

  Color onColor(ThemeData theme) => switch (this) {
    RoleBadgeType.invited ||
    RoleBadgeType.knocking => theme.colorScheme.onSecondaryContainer,
    RoleBadgeType.admin => theme.pangea.onGoldFixed,
    RoleBadgeType.moderator => theme.pangea.onGoldContainer,
  };
}

/// A permission or membership label: the badge across a participant card's
/// avatar, and the Admin label on a Courses hub tile (#9207). Ringed in the
/// surface color, like the avatar's presence dot, so it separates from an
/// avatar image or leaderboard ring it overlaps.
class RoleBadge extends StatelessWidget {
  final RoleBadgeType type;

  const RoleBadge(this.type, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: type.color(theme),
        border: Border.all(color: theme.colorScheme.surface, width: 2),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      ),
      child: Text(
        type.label(L10n.of(context)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(color: type.onColor(theme)),
      ),
    );
  }
}
