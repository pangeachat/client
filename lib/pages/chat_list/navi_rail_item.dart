import 'package:flutter/material.dart';

import 'package:badges/badges.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import '../../config/themes.dart';

class NaviRailItem extends StatelessWidget {
  final String toolTip;
  final bool isSelected;
  final void Function() onTap;
  final Widget icon;
  final Widget? selectedIcon;
  final bool Function(Room)? unreadBadgeFilter;
  // #Pangea
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final bool expanded;
  // Pangea#

  const NaviRailItem({
    required this.toolTip,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    this.selectedIcon,
    this.unreadBadgeFilter,
    // #Pangea
    this.backgroundColor,
    this.borderRadius,
    this.expanded = false,
    // Pangea#
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // #Pangea
    // final borderRadius = BorderRadius.circular(AppConfig.borderRadius);
    final borderRadius = this.borderRadius ?? BorderRadius.circular(10.0);

    final isColumnMode = FluffyThemes.isColumnMode(context);
    final width = isColumnMode
        ? FluffyThemes.navRailWidth
        : FluffyThemes.navRailWidth - 8.0;
    // Pangea#
    final icon = isSelected ? selectedIcon ?? this.icon : this.icon;
    final unreadBadgeFilter = this.unreadBadgeFilter;
    // #Pangea
    // return HoverBuilder(
    return GestureDetector(
      onTap: onTap,
      child: HoverBuilder(
        // Pangea#
        builder: (context, hovered) {
          // #Pangea
          // return SizedBox(
          //   height: 72,
          //   width: FluffyThemes.navRailWidth,
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: width - (isColumnMode ? 16.0 : 12.0),
                width: width,
                // Pangea#
                child: Stack(
                  children: [
                    Positioned(
                      top: 8,
                      bottom: 8,
                      left: 0,
                      child: AnimatedContainer(
                        width: isSelected
                            ? FluffyThemes.isColumnMode(context)
                                  ? 8
                                  : 4
                            : 0,
                        duration: FluffyThemes.animationDuration,
                        curve: FluffyThemes.animationCurve,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(90),
                            bottomRight: Radius.circular(90),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: AnimatedScale(
                        scale: hovered ? 1.1 : 1.0,
                        duration: FluffyThemes.animationDuration,
                        curve: FluffyThemes.animationCurve,
                        // #Pangea
                        // child: Material(
                        //   borderRadius: borderRadius,
                        //   color: isSelected
                        //       ? theme.colorScheme.primaryContainer
                        //       : theme.colorScheme.surfaceContainerHigh,
                        child: UnreadRoomsBadge(
                          filter: unreadBadgeFilter ?? (_) => false,
                          badgePosition: BadgePosition.topEnd(
                            top: 1,
                            end: isColumnMode ? 8 : 4,
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:
                                  backgroundColor ??
                                  (isSelected
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainerHigh),
                              borderRadius: borderRadius,
                            ),
                            margin: EdgeInsets.symmetric(
                              horizontal: isColumnMode ? 16.0 : 12.0,
                              vertical: isColumnMode ? 8.0 : 6.0,
                            ),
                            child: TooltipVisibility(
                              visible: !expanded,
                              // Pangea#
                              child: Tooltip(
                                message: toolTip,
                                child: InkWell(
                                  borderRadius: borderRadius,
                                  // #Pangea
                                  // onTap: onTap,
                                  child: icon,
                                  // child: unreadBadgeFilter == null
                                  //     ? icon
                                  //     : UnreadRoomsBadge(
                                  //         filter: unreadBadgeFilter,
                                  //         badgePosition: BadgePosition.topEnd(
                                  //           top: -12,
                                  //           end: -8,
                                  //         ),
                                  //         child: icon,
                                  //       ),
                                  // Pangea#
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // #Pangea
              if (expanded)
                Flexible(
                  child: Container(
                    height: width - (isColumnMode ? 16.0 : 12.0),
                    padding: const EdgeInsets.only(right: 16.0),
                    child: ListTile(
                      title: Text(
                        toolTip,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      onTap: onTap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 0.0,
                      ),
                    ),
                  ),
                ),
              // Pangea#
            ],
          );
        },
      ),
    );
  }
}
