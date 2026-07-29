import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/map_clipper.dart';
import 'package:fluffychat/pangea/common/widgets/invited_course_badge.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';

class CourseAvatar extends StatelessWidget {
  final Uri? avatar;
  final String displayname;
  final double size;

  /// The unread course-ping future and the course's child-room ids drive the
  /// notification badge. They are only available for real course rooms (nav
  /// rail, joined-courses list); for add-course previews and course-plan
  /// suggestions there is no room yet, so both are null and no badge shows.
  final Future<Event?>? unreadCoursePingEvent;
  final Set<String?>? courseChildrenIds;
  final bool invite;

  final Widget? child;

  const CourseAvatar({
    super.key,
    this.avatar,
    required this.displayname,
    required this.size,
    this.unreadCoursePingEvent,
    this.courseChildrenIds,
    this.invite = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final position = b.BadgePosition.topEnd(top: -5, end: -7);
    final child = ClipPath(
      clipper: MapClipper(),
      child: ExcludeSemantics(
        child: Avatar(
          mxContent: avatar,
          name: displayname,
          border: BorderSide(width: 1, color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(0),
          size: size,
        ),
      ),
    );

    if (invite) {
      return InvitedCourseBadge(position: position, child: child);
    }

    // No underlying room (add-course preview or course-plan suggestion): show
    // the plain avatar without the unread-notification badge.
    final unreadCoursePingEvent = this.unreadCoursePingEvent;
    final courseChildrenIds = this.courseChildrenIds;
    if (unreadCoursePingEvent == null || courseChildrenIds == null) {
      return child;
    }

    return UnreadRoomsBadge(
      filter: (room) => courseChildrenIds.contains(room.id),
      badgePosition: position,
      child: FutureBuilder(
        future: unreadCoursePingEvent,
        builder: (context, snapshot) {
          final eventId = snapshot.data;
          if (eventId != null) {
            return b.Badge(
              badgeStyle: b.BadgeStyle(
                badgeColor: Theme.of(context).colorScheme.primaryContainer,
                elevation: 4,
                borderSide: BorderSide.none,
                padding: const EdgeInsetsGeometry.all(2),
              ),
              badgeContent: Icon(
                Icons.notifications_outlined,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 12,
              ),
              position: position,
              child: child,
            );
          }

          return b.Badge(showBadge: false, position: position, child: child);
        },
      ),
    );
  }
}
