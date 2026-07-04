import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/bot/widgets/bot_settings_language_icon.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/users/member_actions_popup_menu_button.dart';

class ActivityParticipantIndicator extends StatelessWidget {
  final String name;
  final String? userId;
  final User? user;
  final Room? room;

  final VoidCallback? onTap;
  final bool selected;
  final bool selectable;
  final bool shimmer;
  final double opacity;

  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  // When non-null, the card renders in stars mode (role name + star icons)
  // instead of the default avatar/username mode.
  final List<ActivityRoleGoal>? goals;
  final Set<String>? completedGoalIds;

  const ActivityParticipantIndicator({
    super.key,
    required this.name,
    this.user,
    this.room,
    this.userId,
    this.selected = false,
    this.selectable = true,
    this.shimmer = false,
    this.onTap,
    this.opacity = 1.0,
    this.padding,
    this.borderRadius,
    this.goals,
    this.completedGoalIds,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = this.borderRadius ?? BorderRadius.circular(8.0);
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        onTap:
            onTap ??
            (user != null
                ? () => showMemberActionsPopupMenu(
                    context: context,
                    user: user!,
                    room: room,
                  )
                : null),
        child: AbsorbPointer(
          absorbing: !selectable,
          child: HoverBuilder(
            builder: (context, hovered) {
              // Prefer the member's display name over the raw @localpart so a
              // role reads as a human name, not a username (#7366). Falls back
              // to the localpart when the occupant isn't a resolved member.
              final displayName = user?.calcDisplayname() ?? userId?.localpart;
              final avatar = userId != null
                  ? Avatar(
                      mxContent: user?.avatarUrl != null
                          ? user!.avatarUrl!
                          : null,
                      name: displayName ?? userId!.localpart,
                      size: 60.0,
                      userId: userId,
                      miniIcon:
                          room != null && user?.id == BotName.byEnvironment
                          ? BotSettingsLanguageIcon(user: user!)
                          : null,
                      presenceOffset:
                          room != null && user?.id == BotName.byEnvironment
                          ? const Offset(0, 0)
                          : null,
                    )
                  : CircleAvatar(
                      radius: 30.0,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: const Icon(Icons.person, size: 30.0),
                    );
              return Opacity(
                opacity: opacity,
                child: ShimmerBackground(
                  enabled: shimmer && !hovered,
                  borderRadius: borderRadius,
                  child: Container(
                    alignment: Alignment.center,
                    padding:
                        padding ??
                        const EdgeInsets.symmetric(
                          vertical: 4.0,
                          horizontal: 8.0,
                        ),
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      color: (hovered || selected) && selectable
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.surfaceContainerLow,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 4.0,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    height: 125.0,
                    child: goals != null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontSize: 12.0),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              ActivityStarRow(
                                total: goals!.length,
                                earned: goals!
                                    .where(
                                      (g) =>
                                          completedGoalIds?.contains(g.id) ??
                                          false,
                                    )
                                    .length,
                                iconSize: 22.0,
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontSize: 12.0),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              avatar,
                              Text(
                                displayName ?? L10n.of(context).openRoleLabel,
                                style: TextStyle(
                                  fontSize: 12.0,
                                  color:
                                      (Theme.of(context).brightness ==
                                          Brightness.light
                                      ? (displayName?.darkColor ??
                                            theme.colorScheme.primary)
                                      : (displayName?.lightColorText ??
                                            theme.colorScheme.primary)),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
