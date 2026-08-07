import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;

import 'package:fluffychat/config/app_config.dart';

/// The badge on the avatar of a course the learner has been invited to but
/// hasn't joined yet. Gold rather than error-colored, and an envelope rather
/// than a warning glyph: an invitation is an opportunity, not a problem
/// (#7636). Sized to match the unread-ping badge in `CourseAvatar` so the
/// avatar doesn't shift as a course moves between states.
class InvitedCourseBadge extends StatelessWidget {
  final b.BadgePosition? position;
  final Widget? child;

  /// Announces the badge to a screen reader. Null on an avatar the surrounding
  /// tile already labels "Invited" (`add_course_tile.dart`); set where the
  /// badge is the only sign of the invite, as on the narrow Courses tab.
  final String? semanticLabel;

  /// False leaves the child bare. For callers that show the same subtree in
  /// both states — the Courses rail item, which is badged only while an
  /// invitation is waiting — so the button isn't rebuilt from scratch as the
  /// badge comes and goes.
  final bool showBadge;

  const InvitedCourseBadge({
    super.key,
    this.position,
    this.child,
    this.semanticLabel,
    this.showBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return b.Badge(
      showBadge: showBadge,
      badgeStyle: b.BadgeStyle(
        badgeColor: AppConfig.goldByTheme(context),
        elevation: 4,
        borderSide: BorderSide.none,
        padding: const EdgeInsetsGeometry.all(2),
      ),
      badgeContent: Icon(
        Icons.mail,
        color: AppConfig.onGoldByTheme(context),
        size: 12,
        semanticLabel: semanticLabel,
      ),
      position: position,
      child: child,
    );
  }
}
