import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The activity and session a course ping pointed at.
typedef CoursePingBadgeData = ({
  String courseId,
  String activityId,
  String sessionRoomId,
});

/// In-memory carrier for the ping the learner is following (#8319).
///
/// The ping's read marker is set the moment the course page opens
/// ([SpaceDetailsController._handleCoursePing]), so the unread event can't be
/// re-queried by the surfaces that badge the pinged activity — the course
/// plan's card list and the activity's join-session list. The course page
/// stashes the ping here before marking it read; the next visit to the same
/// course with no unread ping clears it, which is what makes the badges
/// disappear once the learner backs out and returns.
class CoursePingBadgeCache {
  CoursePingBadgeCache._();

  static final ValueNotifier<CoursePingBadgeData?> instance = ValueNotifier(
    null,
  );

  /// The learner opened the pinged activity, so the ping has served its
  /// purpose and the next return to the course may clear it.
  static bool _followed = false;

  static void set(CoursePingBadgeData data) {
    // Re-capturing the SAME unread ping (a second course-page mount racing
    // the read marker's round trip) must not reset the followed flag.
    if (instance.value != data) _followed = false;
    instance.value = data;
  }

  /// Record that the activity a ping pointed at was opened. Hooked where the
  /// activity start page mounts, so it covers the course-plan card, a map
  /// pin, and a deep link alike.
  static void markFollowed(String activityId) {
    if (instance.value?.activityId == activityId) _followed = true;
  }

  /// Called by a course-page mount that found no unread ping. Only a FOLLOWED
  /// ping is cleared: the read marker is set the moment the course page first
  /// opens, so a premature remount (compact peek expanding, a route rebuild)
  /// finds the ping already read and would otherwise wipe the badges before
  /// the learner ever saw them.
  static void clearForCourse(String courseId) {
    if (_followed && instance.value?.courseId == courseId) {
      instance.value = null;
    }
  }
}

/// The circular bell badge marking the pinged activity card / session tile.
/// Its fill is the Open/joinable state green ([ActivityPinState.joinable]) so
/// it reads as part of the open session it points at, per the #8319 designs.
class CoursePingBadge extends StatelessWidget {
  final double size;

  const CoursePingBadge({this.size = 24.0, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: L10n.of(context).pingedLabel,
      child: Material(
        color: AppConfig.green,
        elevation: 4.0,
        shape: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.notifications_outlined,
            size: size * 0.6,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
