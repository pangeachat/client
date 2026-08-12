import 'package:flutter/material.dart';

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
/// ([ChatDetailsController._handleCoursePing]), so the unread event can't be
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

  static void set(CoursePingBadgeData data) => instance.value = data;

  static void clearForCourse(String courseId) {
    if (instance.value?.courseId == courseId) instance.value = null;
  }
}

/// The circular bell badge marking the pinged activity card / session tile.
/// Matches the ping badge on the course avatar ([CourseAvatar]).
class CoursePingBadge extends StatelessWidget {
  final double size;

  const CoursePingBadge({this.size = 24.0, super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: L10n.of(context).pingedLabel,
      child: Material(
        color: scheme.primaryContainer,
        elevation: 4.0,
        shape: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.notifications_outlined,
            size: size * 0.6,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
