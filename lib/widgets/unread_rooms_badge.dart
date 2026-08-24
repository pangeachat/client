import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'matrix.dart';

class UnreadRoomsBadge extends StatelessWidget {
  final bool Function(Room) filter;
  final b.BadgePosition? badgePosition;
  final Widget? child;

  const UnreadRoomsBadge({
    super.key,
    required this.filter,
    this.badgePosition,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // #Pangea
    // final unreadCount = Matrix.of(context).client.rooms
    final counted = Matrix.of(context).client.rooms
        .where((r) => !r.isHiddenRoom && !r.isSpace)
        // Pangea#
        .where(filter)
        .where((r) => (r.isUnread || r.membership == Membership.invite))
        // #Pangea
        .toList();
    final unreadCount = counted.length;

    // At least one of the counted rooms is an invitation waiting on the
    // learner, so the badge wears the invited gold instead of the ordinary
    // unread purple — the same colour the invited course tile and its avatar
    // badge wear, so an unanswered invite reads the same wherever it surfaces
    // (#8191). It still carries the full unread count: the gold says something
    // about what is in the count, it doesn't change the count.
    //
    // `isPendingInvite` excludes an approved knock, which arrives wearing
    // `Membership.invite` but is the learner's own request coming back
    // answered. Same test the chat list row's chip uses, so a gold badge
    // always has a gold row behind it.
    final hasInvite = counted.any((r) => r.isPendingInvite);
    // Pangea#
    final unreadText = unreadCount < 100
        ? unreadCount.toString()
        : L10n.of(context).unreadPlus;
    return b.Badge(
      badgeStyle: b.BadgeStyle(
        // #Pangea
        padding: const EdgeInsetsGeometry.all(1),
        badgeColor: hasInvite
            ? AppConfig.goldByTheme(context)
            : theme.colorScheme.primary,
        // Pangea#
        elevation: 4,
        borderSide: BorderSide(color: theme.colorScheme.surface, width: 2),
      ),
      // #Pangea
      // badgeContent: Text(
      //   unreadCount.toString(),
      //   style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 12),
      // ),
      badgeContent: SizedBox(
        width: 15,
        height: 15,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            unreadText,
            semanticsLabel: L10n.of(context).unreadLabel(unreadText),
            style: TextStyle(
              color: hasInvite
                  ? AppConfig.onGoldByTheme(context)
                  : theme.colorScheme.onPrimary,
              fontSize: 12,
            ),
          ),
        ),
      ),
      // Pangea#
      showBadge: unreadCount != 0,
      badgeAnimation: const b.BadgeAnimation.scale(),
      position: badgePosition ?? b.BadgePosition.bottomEnd(),
      child: child,
    );
  }
}
