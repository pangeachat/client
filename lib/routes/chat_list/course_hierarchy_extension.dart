import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

extension SpaceRoomsChunkTypeExtension on SpaceRoomsChunk$2 {
  bool get isActivitySession =>
      roomType?.startsWith(PangeaRoomTypes.activitySession) == true;
}

/// A course space's hierarchy children — the rooms in the course that the
/// user is not in yet, which `client.rooms` cannot show.
extension CourseHierarchyExtension on Room {
  /// The failsafe cap on hierarchy calls to the server per scan: a busy
  /// course has more children than fit on one page (every activity session
  /// and every member's analytics room is one).
  static const int maxHierarchyPages = 5;

  static const int hierarchyPageSize = 100;

  /// This course's direct hierarchy children, fetched a page at a time as
  /// they are read, so a caller that stops early stops the paging too.
  Stream<SpaceRoomsChunk$2> hierarchyChildren() async* {
    String? from;
    for (int page = 0; page < maxHierarchyPages; page++) {
      final response = await client.getSpaceHierarchy(
        id,
        maxDepth: 1,
        from: from,
        limit: hierarchyPageSize,
      );
      yield* Stream.fromIterable(response.rooms);
      from = response.nextBatch;
      if (from == null) return;
    }
  }

  /// Whether [child], from this course's hierarchy, is one the course's chat
  /// list offers to join: not the course itself, not a room the user is
  /// already in, invited to or knocking on (those are listed from
  /// `client.rooms`), not an analytics room, and not marked unsuggested.
  bool isJoinableChild(SpaceRoomsChunk$2 child) {
    if (child.roomId == id) return false;
    final room = client.getRoomById(child.roomId);
    if (room != null && room.membership != Membership.leave) return false;
    return child.roomType != PangeaRoomTypes.analytics &&
        (spaceChildSuggestionStatus[child.roomId] ?? true);
  }

  /// Whether this course has a group chat the user can join but has not.
  Future<bool> hasJoinableGroupChat() => hierarchyChildren().any(
    (child) => isJoinableChild(child) && !child.isActivitySession,
  );
}
