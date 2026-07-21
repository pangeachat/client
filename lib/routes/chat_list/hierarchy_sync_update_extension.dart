import 'package:matrix/matrix_api_lite.dart';

extension HierarchySyncUpdateExtension on SyncUpdate {
  /// Used to filter out sync updates with hierarchy updates for the active
  /// space so that the view can be auto-reloaded in the room subscription
  bool hasHierarchyUpdate({
    required String roomId,
    required String? userID,
    required Set<String> childrenIds,
  }) {
    final joinUpdate = rooms?.join;
    final inviteUpdate = rooms?.invite;
    final leaveUpdate = rooms?.leave;
    if (joinUpdate == null && leaveUpdate == null && inviteUpdate == null) {
      return false;
    }

    final joinedRooms = joinUpdate?.entries
        .where((e) => childrenIds.contains(e.key))
        .map((e) => e.value.timeline?.events)
        .whereType<List<MatrixEvent>>();

    final invitedRooms = inviteUpdate?.entries
        .where((e) => childrenIds.contains(e.key))
        .map((e) => e.value.inviteState)
        .whereType<List<StrippedStateEvent>>();

    final leftRooms = leaveUpdate?.entries
        .where((e) => childrenIds.contains(e.key))
        .map((e) => e.value.timeline?.events)
        .whereType<List<MatrixEvent>>();

    final bool hasJoinedRoom =
        joinedRooms?.any(
          (events) => events.any(
            (e) => e.senderId == userID && e.type == EventTypes.RoomMember,
          ),
        ) ??
        false;

    final bool hasLeftRoom =
        leftRooms?.any(
          (events) => events.any(
            (e) => e.senderId == userID && e.type == EventTypes.RoomMember,
          ),
        ) ??
        false;

    if (hasJoinedRoom || hasLeftRoom || (invitedRooms?.isNotEmpty ?? false)) {
      return true;
    }

    final joinTimeline = joinUpdate?[roomId]?.timeline?.events;
    final leaveTimeline = leaveUpdate?[roomId]?.timeline?.events;
    if (joinTimeline == null && leaveTimeline == null) return false;

    final bool hasJoinUpdate =
        joinTimeline?.any((event) => event.type == EventTypes.SpaceChild) ??
        false;
    final bool hasLeaveUpdate =
        leaveTimeline?.any((event) => event.type == EventTypes.SpaceChild) ??
        false;
    return hasJoinUpdate || hasLeaveUpdate;
  }
}
