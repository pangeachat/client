import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:matrix/matrix.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/member_actions_popup_menu_button.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap ??
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
              final avatar = userId != null
                  ? user?.avatarUrl == null ||
                          user!.avatarUrl!.toString().startsWith("mxc")
                      ? Avatar(
                          mxContent:
                              user?.avatarUrl != null ? user!.avatarUrl! : null,
                          name: userId!.localpart,
                          size: 60.0,
                          userId: userId,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: CachedNetworkImage(
                            imageUrl: user!.avatarUrl!.toString(),
                            width: 60.0,
                            height: 60.0,
                            fit: BoxFit.cover,
                          ),
                        )
                  : CircleAvatar(
                      radius: 30.0,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: const Icon(
                        Icons.question_mark,
                        size: 30.0,
                      ),
                    );
              return Opacity(
                opacity: opacity,
                child: Container(
                  padding: padding ??
                      const EdgeInsets.symmetric(
                        vertical: 4.0,
                        horizontal: 8.0,
                      ),
                  decoration: BoxDecoration(
                    borderRadius: borderRadius ?? BorderRadius.circular(8.0),
                    color: (hovered || selected) && selectable
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.surface.withAlpha(130),
                  ),
                  height: 125.0,
                  constraints: const BoxConstraints(maxWidth: 100.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      shimmer && !selected
                          ? Shimmer.fromColors(
                              baseColor: AppConfig.gold.withAlpha(20),
                              highlightColor: AppConfig.gold.withAlpha(50),
                              child: avatar,
                            )
                          : avatar,
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        userId?.localpart ?? L10n.of(context).openRoleLabel,
                        style: TextStyle(
                          fontSize: 12.0,
                          color: (Theme.of(context).brightness ==
                                  Brightness.light
                              ? (userId?.localpart?.darkColor ?? name.darkColor)
                              : (userId?.localpart?.lightColorText ??
                                  name.lightColorText)),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
