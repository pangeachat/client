import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';

/// Whether the learner has a saved session of an activity — they pressed
/// "I'm done" and the session was saved. What the completed mark on a chat
/// row replaying a finished activity reads; every other completed stamp
/// reads XP ([QuestsClientExtension.savedSessionsByActivity], #9559).
extension SavedActivitiesClientExtension on Client {
  /// Whether [activityId] has a saved session — a single pass over `rooms`
  /// that stops at the first match.
  bool hasSavedSessionOf(String activityId) => rooms.any(
    (room) => room.activityId == activityId && room.hasArchivedActivity,
  );
}
