import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;

class InvitedCourseBadge extends StatelessWidget {
  final b.BadgePosition? position;
  final Widget? child;

  const InvitedCourseBadge({super.key, this.position, this.child});

  @override
  Widget build(BuildContext context) {
    return b.Badge(
      badgeStyle: b.BadgeStyle(
        badgeColor: Theme.of(context).colorScheme.error,
        elevation: 4,
        borderSide: BorderSide.none,
        padding: const EdgeInsetsGeometry.all(0),
      ),
      badgeContent: Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.onPrimary,
        size: 16,
      ),
      position: position,
      child: child,
    );
  }
}
