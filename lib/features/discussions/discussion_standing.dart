import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/discussions/discussion_extensions.dart';

/// Where the learner stands in one discussion: their rooms for it where they
/// hold a seat. A room a course admin was joined to on its creation, to
/// observe it, is not theirs until they tap Join and take a seat there, so
/// the discussion opens its start page for them.
class DiscussionStanding {
  /// Their room while they are still in the discussion: not ended. It shows
  /// the discussion as Joined and carries its unread bubble.
  final Room? activeRoom;

  /// Their room once they have ended the discussion ("I'm done").
  final Room? endedRoom;

  const DiscussionStanding({this.activeRoom, this.endedRoom});

  bool get joined => activeRoom != null;

  /// They have ended it: its card reads Answered.
  bool get answered => activeRoom == null && endedRoom != null;

  /// The room opening the discussion goes back to.
  Room? get room => activeRoom ?? endedRoom;

  DiscussionStanding _including(Room room) =>
      (room.ownRoleState?.isFinished ?? false)
      ? DiscussionStanding(activeRoom: activeRoom, endedRoom: endedRoom ?? room)
      : DiscussionStanding(
          activeRoom: activeRoom ?? room,
          endedRoom: endedRoom,
        );
}

extension DiscussionClientExtension on Client {
  DiscussionStanding discussionStandingFor(String activityId) {
    var standing = const DiscussionStanding();
    for (final room in rooms) {
      if (room._seatedDiscussionId == activityId) {
        standing = standing._including(room);
      }
    }
    return standing;
  }

  /// [discussionStandingFor] every discussion the learner holds a seat in,
  /// by activity id, from one pass over their rooms.
  Map<String, DiscussionStanding> get discussionStandings {
    final standings = <String, DiscussionStanding>{};
    for (final room in rooms) {
      final id = room._seatedDiscussionId;
      if (id == null) continue;
      standings[id] = (standings[id] ?? const DiscussionStanding())._including(
        room,
      );
    }
    return standings;
  }
}

extension on Room {
  /// The discussion this room is the learner's own seat in: joined, and
  /// holding a seat. The room-type checks come first, so only discussion
  /// rooms parse their roles.
  String? get _seatedDiscussionId {
    if (membership != Membership.join) return null;
    final id = discussionActivityId;
    return id != null && ownRoleState != null ? id : null;
  }
}
