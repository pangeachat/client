import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';

class UnreadBubble extends StatelessWidget {
  final Room room;

  /// When set, draws a border of this colour around the bubble so it stands
  /// out against a same-coloured background
  final Color? borderColor;

  const UnreadBubble({required this.room, this.borderColor, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = room.isUnread;
    final hasNotifications = room.notificationCount > 0;
    final unreadBubbleSize = unread || room.hasNewMessages
        ? room.notificationCount > 0
              ? 20.0
              : 14.0
        : 0.0;
    final borderWidth = borderColor != null ? 1.5 : 0.0;
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      height: unreadBubbleSize == 0 ? 0 : unreadBubbleSize + borderWidth * 2,
      width: !hasNotifications && !unread && !room.hasNewMessages
          ? 0
          : (unreadBubbleSize - 9) * room.notificationCount.toString().length +
                9 +
                borderWidth * 2,
      decoration: BoxDecoration(
        color: room.highlightCount > 0
            ? theme.colorScheme.error
            : hasNotifications || room.markedUnread
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(7),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: hasNotifications
          ? Text(
              room.notificationCount.toString(),
              style: TextStyle(
                color: room.highlightCount > 0
                    ? theme.colorScheme.onError
                    : hasNotifications
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            )
          : const SizedBox.shrink(),
    );
  }
}
