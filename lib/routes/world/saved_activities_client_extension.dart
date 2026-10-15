import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';

/// The activities the learner has a saved session of — they pressed "I'm
/// done" and the session was saved. What the completed stamp marks, on the
/// map and on a chat row replaying a finished activity.
extension SavedActivitiesClientExtension on Client {
  /// Every activity with a saved session, in one pass over `rooms`.
  Set<String> get savedActivityIds => {
    for (final room in rooms)
      if (room.hasArchivedActivity) ?room.activityId,
  };

  /// Whether [activityId] has a saved session — a single pass over `rooms`
  /// that stops at the first match.
  bool hasSavedSessionOf(String activityId) => rooms.any(
    (room) => room.activityId == activityId && room.hasArchivedActivity,
  );
}
