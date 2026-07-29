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

  const InvitedCourseBadge({super.key, this.position, this.child});

  @override
  Widget build(BuildContext context) {
    return b.Badge(
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
      ),
      position: position,
      child: child,
    );
  }
}
