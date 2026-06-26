import 'package:flutter/material.dart';

import 'package:badges/badges.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import '../config/themes.dart';

class NaviRailItem extends StatelessWidget {
  final String toolTip;
  final bool isSelected;
  final void Function() onTap;
  final Widget icon;
  final Widget? selectedIcon;
  final bool Function(Room)? unreadBadgeFilter;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final double naviRailWidth;

  const NaviRailItem({
    required this.toolTip,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    this.selectedIcon,
    this.unreadBadgeFilter,
    required this.naviRailWidth,
    this.backgroundColor,
    this.borderRadius,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = this.borderRadius ?? BorderRadius.circular(10.0);

    final isColumnMode = FluffyThemes.isColumnMode(context);
    final height = naviRailWidth - (isColumnMode ? 16.0 : 12.0);

    final icon = isSelected ? selectedIcon ?? this.icon : this.icon;
    final unreadBadgeFilter = this.unreadBadgeFilter;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: HoverBuilder(
          builder: (context, hovered) {
            return Container(
              height: height,
              decoration: BoxDecoration(color: theme.colorScheme.surface),
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
                      child: UnreadRoomsBadge(
                        filter: unreadBadgeFilter ?? (_) => false,
                        badgePosition: BadgePosition.topEnd(
                          top: 1,
                          end: isColumnMode ? 8 : 4,
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          margin: EdgeInsets.symmetric(
                            horizontal: isColumnMode ? 16.0 : 12.0,
                            vertical: isColumnMode ? 8.0 : 6.0,
                          ),
                          // Material + InkWell give the item real Material
                          // interaction states — hover overlay, pressed
                          // ripple, focus. The InkWell's own borderRadius
                          // bounds the ripple; no Material clip, so angular
                          // icons (e.g. the Pangea mark) aren't cut.
                          child: Material(
                            color:
                                backgroundColor ??
                                (isSelected
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHigh),
                            borderRadius: borderRadius,
                            child: Tooltip(
                              message: toolTip,
                              child: InkWell(
                                borderRadius: borderRadius,
                                onTap: onTap,
                                child: icon,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
