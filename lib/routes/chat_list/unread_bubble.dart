import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';

/// The unread indicator shown on a chat list row, a world map pin, and a world
/// map large card: a **fixed-diameter circle**, never a pill that widens with
/// the count. A count that outgrows the circle is scaled down to fit, and
/// anything past 99 reads as `99+` — the same treatment the All-Chats nav badge
/// gives its count ([UnreadRoomsBadge]), so the two read as one family (#8007).
/// Letting the bubble stretch instead made three- and four-digit counts elbow
/// the row's other content in the narrow space a chat list row has.
class UnreadBubble extends StatelessWidget {
  final Room room;

  /// When set, draws a border of this colour around the bubble so it stands
  /// out against a same-coloured background
  final Color? borderColor;

  const UnreadBubble({required this.room, this.borderColor, super.key});

  /// Diameter of the circle when it carries a count.
  static const double _countDiameter = 20.0;

  /// Diameter of the plain "there's something new here" dot — no count.
  static const double _dotDiameter = 14.0;

  /// The square the count is fitted into, inset from the circle's edge so a
  /// scaled-down `99+` still clears the ring. Matches [UnreadRoomsBadge]'s box.
  static const double _countBox = 15.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = room.isUnread;
    final hasNotifications = room.notificationCount > 0;
    final unreadBubbleSize = unread || room.hasNewMessages
        ? hasNotifications
              ? _countDiameter
              : _dotDiameter
        : 0.0;
    final borderWidth = borderColor != null ? 1.5 : 0.0;
    final diameter = unreadBubbleSize == 0
        ? 0.0
        : unreadBubbleSize + borderWidth * 2;
    final countText = room.notificationCount < 100
        ? room.notificationCount.toString()
        : L10n.of(context).unreadPlus;
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      height: diameter,
      width: diameter,
      decoration: BoxDecoration(
        color: room.highlightCount > 0
            ? theme.colorScheme.error
            : hasNotifications || room.markedUnread
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: hasNotifications
          // The count lives in a box inset from the circle's edge and shrinks
          // to fit it, so `8`, `42` and `99+` all sit inside the same circle
          // rather than widening it.
          ? SizedBox(
              width: _countBox,
              height: _countBox,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  countText,
                  semanticsLabel: L10n.of(context).unreadLabel(countText),
                  style: TextStyle(
                    color: room.highlightCount > 0
                        ? theme.colorScheme.onError
                        : theme.colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
