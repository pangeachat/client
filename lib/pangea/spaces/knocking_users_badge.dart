import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;

import 'package:fluffychat/l10n/l10n.dart';

/// The badge on the avatar of a course someone is knocking on: a white "!"
/// in an error-colored circle, matching the red bell of the in-course knock
/// notification so the two read as the same alert (#8139). Admin-only — the
/// caller gates on knocking users being present, which `Room.knockingUsers`
/// already restricts to admins. Sized to match the unread-ping badge in
/// `CourseAvatar` so the avatar doesn't shift as a course moves between
/// states.
class KnockingUsersBadge extends StatelessWidget {
  /// The glyph a pending knock is drawn with, wherever it surfaces — this
  /// badge and the course page's join-request card — so the two read as the
  /// same alert. Distinct from the bell, which stays the course-ping mark
  /// (#8462).
  static const IconData icon = Icons.priority_high;

  final b.BadgePosition? position;
  final Widget? child;

  const KnockingUsersBadge({super.key, this.position, this.child});

  @override
  Widget build(BuildContext context) {
    return b.Badge(
      badgeStyle: b.BadgeStyle(
        badgeColor: Theme.of(context).colorScheme.error,
        elevation: 4,
        borderSide: BorderSide.none,
        padding: const EdgeInsetsGeometry.all(2),
      ),
      badgeContent: Icon(
        icon,
        color: Theme.of(context).colorScheme.onError,
        size: 12,
        semanticLabel: L10n.of(context).aUserIsKnocking,
      ),
      position: position,
      child: child,
    );
  }
}
