import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_settings_language_icon.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
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
    final borderRadius = this.borderRadius ?? BorderRadius.circular(8.0);
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
                          miniIcon:
                              room != null && userId == BotName.byEnvironment
                                  ? BotSettingsLanguageIcon(user: user!)
                                  : null,
                          presenceOffset:
                              room != null && userId == BotName.byEnvironment
                                  ? const Offset(0, 0)
                                  : null,
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
                child: ShimmerBackground(
                  enabled: shimmer,
                  borderRadius: borderRadius,
                  child: Container(
                    alignment: Alignment.center,
                    padding: padding ??
                        const EdgeInsets.symmetric(
                          vertical: 4.0,
                          horizontal: 8.0,
                        ),
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      color: (hovered || selected) && selectable
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.surface.withAlpha(130),
                    ),
                    height: 125.0,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        avatar,
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 12.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          userId?.localpart ?? L10n.of(context).openRoleLabel,
                          style: TextStyle(
                            fontSize: 12.0,
                            color: (Theme.of(context).brightness ==
                                    Brightness.light
                                ? (userId?.localpart?.darkColor ??
                                    name.darkColor)
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
